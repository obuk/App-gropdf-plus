package App::gropdf::OpenType;

use strict;
use warnings;
require 5.8.0;
#use 5.008001;
use Carp;
use Encode;
use List::Util qw(min);
use File::Temp  qw/tempfile/;
use Unicode::Normalize;
use Unicode::UCD qw/charblocks/;
use Font::TTF::Font;

use App::gropdf::Base qw(:all);

my $prefer_utf16 = 1;    # reduces encoding/decoding by using utf16 as is

# Table 119
my $Predefined_CMap_names = qr/^Adobe-(GB1|CNS1|Japan1|Korea1|)-\d+$/;

use Class::Tiny qw( fontno fnt cidfont );

sub new {
    my $class = shift;
    my $self = bless { @_ }, $class;
    $self->init;
    $self;
}

sub init {
    my ($self) = @_;

    confess "fontno is required" unless defined $self->fontno;
    confess "cidfont is required" unless defined $self->cidfont;

    if ($self->{opentype}) {
	unless (ref $self->{opentype}) {
	    my %feature;
	    for (split /\s+/, $self->{opentype}) {
		my ($f, $x) = split /=/;
		$feature{$f} = $x;
	    }
	    $self->{opentype} = \%feature;
	}
    }

    $self->{optimize} = 0;
    $self->{optimize} |= 1;	# reuse font object
    $self->{optimize} |= 2;	# share subset font

    my $otf;

    if ($self->{optimize} & 1) {
	# reuses font objects remaining in %fontlst to reduce font
	# loading time.
	for (grep defined $_->{FNT}->{' OTF'}, values %fontlst) {
	    $otf = $_->{FNT}->{' OTF'}, last
		if $_->{FNT}->{fontfile} eq $self->{fontfile};
	}
    }
    $otf //= Font::TTF::Font->open($self->{fontfile});
    $self->{' OTF'} = $otf;

    while (my ($f, $x) = each %{$self->{opentype}}) {
	next if defined $self->{" \U$f\E"};
	next if !defined $x;
	die "cant $f; $@" unless __PACKAGE__->can($f);
	no strict 'refs';
	$otf->{uc $f}->read;
	$self->{" \U$f\E"} = &$f($otf, split /,/, $x);
    }

    $otf->{'CFF '}->read unless $otf->{'CFF '}{TopDICT};
    my $gid2cid = $otf->{'CFF '}->Charset->{code};
    my $cid2gid;
    for my $gid (0 .. $#{$gid2cid}) {
	my $cid = $gid2cid->[$gid];
	$cid2gid->[$cid] = $gid if defined $cid;
    }

    $self->{' CID2GID'} = $cid2gid;
    if (my $cidfont = $self->cidfont) {
	#my $ROS = $otf->{'CFF '}->TopDICT->{ROS};
	my $ROS = [split '-', $cidfont];
	$self->{' CIDSystemInfo'} = {
	    Registry   => "($ROS->[0])",
	    Ordering   => "($ROS->[1])",
	    Supplement => $ROS->[2],
	};
    }

    # table 119
    $self->{' CIDSystemInfo'} //= {
        Registry   => "(Adobe)",
        Ordering   => "(UCS)",
        Supplement => 0,
    };

    $self->{' Encoding'} = join '-', "Identity", $self->{vertical} ? "V" : "H";
    $self->{' CMapName'} = join '-', 'Adobe', 'Identity', 'UCS';

    $otf->{name}->read;
    #$self->{' FontName'} = get_name($otf, 6); # same as internalname
    $self->{' FamilyName'} = get_name($otf, 1);
    $self->{' Notice'}     = get_name($otf, 0);
    $self->{' Weight'}     = get_name($otf, 2);

    $otf->{'post'}->read;
    for (qw/isFixedPitch ItalicAngle/) {
	$self->{" $_"} =
	    exists $otf->{'post'}{STRINGS}{lcfirst $_}
	    ? $otf->{'post'}{STRINGS}{lcfirst $_}
	    : exists $otf->{'post'}{lcfirst $_}
	    ? $otf->{'post'}{lcfirst $_}
	    : exists $otf->{'CFF '}->TopDICT->{lcfirst $_}
	    ? $otf->{'CFF '}->TopDICT->{lcfirst $_}
	    : exists $otf->{'CFF '}->TopDICT->{ucfirst $_}
	    ? $otf->{'CFF '}->TopDICT->{ucfirst $_}
	    : undef;
	#$self->{" $_"} = $self->{" $_"}? 'true' : 'false' if /^[iI]s/;
    }

    if ($self->{' ItalicAngle'} == 0 && $self->{slant}) {
	my $angle = -$self->{slant};
	$angle = rad($angle);

	# see Figure 13 in PDF 32000-1:2008
	$self->{' skew'} = sin($angle) / cos($angle);
    }

    $self->{' FontBBox'} = $otf->{'CFF '}->TopDICT->{FontBBox};

    $otf->{'OS/2'}->read;
    $self->{' Ascender'}  = $otf->{'OS/2'}{sTypoAscender};
    $self->{' Descender'} = $otf->{'OS/2'}{sTypoDescender};
    $self->{' CapHeight'} = $otf->{'OS/2'}{CapHeight};

    $self->{' DW'}  = 1000;
    $self->{' DW2'} = [1000 + $self->{' Descender'}, -1000];

    # sets nospace to 1. However, this does not mean that space glyph do
    # not exist in cidfont. This is to disable the USESPACE option in
    # cidfont.

    $self->{ALLOC} = 0;
    $self->{nospace} = !$self->has_space;
    if (!$self->{nospace}) {
	my ($chf, $ch) = $self->GetNAM('space');
	if ($chf) {
	    $self->AssignGlyph($chf, $ch);
	    $self->{spacewidth} = 270 if !exists $self->{spacewidth};
	}
    }

    $self;
}

sub get_name {
    my ($otf, $number, $platform_id, $encoding_id, $language_id) = @_;
    $platform_id //= 3;
    $encoding_id //= 1;
    $language_id //= 0x409;
    $otf->{name}->read;
    $otf->{name}{strings}[$number][$platform_id][$encoding_id]{$language_id};
}

sub glyphs {
    my $self = shift;

    my $glyphs  = '/.notdef';
    $glyphs .= '/space'	if defined($self->{NO}->[32]) and $self->{NO}->[32] eq 'space';

    my $chars = $self->{TRFCHAR};
    for (my $j = 0; $j <= $#{$chars}; $j++) {
	$glyphs .= join('', @{$self->{CHARSET}->[$j]});
    }

    $glyphs;
}


sub build_fontobject {
    my ($self) = @_;

    # Type 0 Font dictionary (Table 121)
    my $font_dictionary = $self->type0_font_dictionary;
    my $fontnm = $self->fontno;
    $pages->{'Resources'}->{'Font'}->{'F'.$fontnm} = $self->{OBJ} = $font_dictionary;

    # Font descriptor (Table 122)
    my $font_descriptor = $self->font_descriptor;

    # CIDFont dictionary (Table 117)
    my $cid_font = $self->cid_font_dictionary;
    if (my $p = GetObj($cid_font)) {
	$p->{FontDescriptor} = $font_descriptor;
    }
    if (my $p = GetObj($font_dictionary)) {
	$p->{DescendantFonts} = [ $cid_font ];
    }

    # ToUnicode CMaps (9.10.3)
    if (my $tounicode = $self->tounicode_cmap) {
	if (my $p = GetObj($font_dictionary)) {
	    $p->{ToUnicode} = $tounicode;
	}
    }

    # $self->{' embed'} is a flag that requests font embedding.  this
    # flag is passed via %fnt in LoadFont. This can be confusing because
    # %fnt is a section directive in groff fonts, and also the path to
    # the download file without the asterisk at the beginning.
    $self->{' embed'} = 1 if ($options & EMBGSUB) && $self->{opentype}{gsub};

    if (($self->{' embed'} || $embedall) && !($options & NOFILE)) {
	$self->embed_fontfile;
    }
}

sub embed_fontfile {
    my ($self) = @_;

    my @fontno;
    my $f;

    if ($self->{optimize} & 2) {

	# creates subset font containing all CIDs of @fontno. (creates
	# subset font that can be shared by all fonts that has same
	# internalname.) Then, all fonts of @fontno use the subset font.

	for my $fontno (keys %fontlst) {
	    my $fnt = $fontlst{$fontno}{FNT};
	    next unless $fnt->{internalname} eq $self->{internalname};
	    push @fontno, $fontno;
	}
	for my $fontno (@fontno) {
	    my $fnt = $fontlst{$fontno}{FNT};
	    next unless my $font_dictionary = $fnt->{OBJ};
	    next unless my $p = GetObj($font_dictionary);
	    next unless $p->{DescendantFonts};
	    next unless my $cid_font = $p->{DescendantFonts}->[0];
	    next unless my $q = GetObj($cid_font);
	    next unless my $font_descriptor = $q->{FontDescriptor};
	    next unless my $r = GetObj($font_descriptor);
	    next unless $r->{FontName};
	    next unless length($r->{FontName}) > length($self->{internalname});
	    my $plus_name = substr $r->{FontName}, -length($self->{internalname}) - 1;
	    next unless $plus_name eq "+$self->{internalname}";
	    $f = {
		FONTFILE => $r->{FontFile3},
		FONTNAME => $r->{FontName},
	    };
	    last;
	}
    } else {
	@fontno = $self->fontno;
    }

    unless ($f) {
	my %seen;
	my @cid = grep !$seen{$_}++, map $_->[PSNAME],
	    map @{$fontlst{$_}{FNT}{SUB}}, @fontno;
	if (@cid == 0) {
	    ;
	} elsif (my $font_stream = $self->subset(\@cid)) {
	    my $fontfile = BuildObj(++$objct, {
		"Subtype" => "/CIDFontType0C",
	    });
	    $obj[$objct]->{STREAM} = $font_stream;
	    $obj[$objct]->{DATA}{Length} = length $font_stream;
	    $f = {
		FONTFILE => $fontfile,
		FONTNAME => "/".SubTag().$self->{internalname},
	    };
	} else {
	    Die("can't subset $self->{internalname} ($self->{name})");
	}
    }
    return unless $f;

    my $font_dictionary = $self->{OBJ};
    my $cid_font;
    my $font_descriptor;
    if (my $p = GetObj($font_dictionary)) {
	$cid_font = $p->{DescendantFonts}->[0];
	if (my $q = GetObj($cid_font)) {
	    $font_descriptor = $q->{FontDescriptor};
	}
    }

    # Table 127 – Additional entries in an embedded font stream dictionary
    if ($font_descriptor) {
	if (my $p = GetObj($font_descriptor)) {
	    $p->{FontFile3} = $f->{FONTFILE};
	    $p->{FontName} = $f->{FONTNAME};
	}
	if (my $p = GetObj($font_dictionary)) {
	    $p->{BaseFont} = $f->{FONTNAME};
	}
	if (my $p = GetObj($cid_font)) {
	    $p->{BaseFont} = $f->{FONTNAME};
	}
    }
}


sub type0_font_dictionary {
    my ($self) = @_;

    # Type 0 Font dictionary (Table 121)
    my $font_dictionary = BuildObj(++$objct, {
	Type => "/Font",
	Subtype => "/Type0",
	BaseFont => "/".$self->{internalname},
	Encoding => "/".$self->{' Encoding'},
	#DescendantFonts => [ $cid_font ],
	# ToUnicode => undef,
    });

    $font_dictionary;
}

sub font_descriptor {
    my ($self) = @_;

    my $flags = 0;
    #$flags += 1 << ( 1 - 1); # FixedPitch
    $flags += 1 << ( 1 - 1) if $self->{' isFixedPitch'};
    #$flags += 1 << ( 2 - 1); # Serif
    my $re_sans  = qr/Sans/i;
    my $re_serif = qr/Serif|Mincho|Times|Georgia|Baskerville|Garamond/i;
    my $serif = $self->{special}	            ? 0
	: $self->{internalname} =~ $re_serif ? 1
	: $self->{internalname} =~ $re_sans  ? 0
	:                                     0;
    $flags += 1 << ( 2 - 1) if $serif;
    #$flags += 1 << ( 3 - 1); # Symbolic
    $flags += 1 << ( 3 - 1) if $self->{special};
    #$flags += 1 << ( 4 - 1); # Script
    #$flags += 1 << ( 6 - 1); # Nonsymbolic
    $flags += 1 << ( 6 - 1) if !$self->{special};
    #$flags += 1 << ( 7 - 1); # Italic
    $flags += 1 << ( 7 - 1) if $self->{' ItalicAngle'};
    #$flags += 1 << (17 - 1); # AllCap
    #$flags += 1 << (18 - 1); # SmallCap
    #$flags += 1 << (19 - 1); # ForceBold

    # Font descriptor (Table 122)
    BuildObj(++$objct, {
	Type	    => "/FontDescriptor",
	FontName    => "/".$self->{internalname},
	Flags       => $flags,
	FontBBox    => $self->{' FontBBox'},
	ItalicAngle => $self->{' ItalicAngle'},
	Ascent	    => $self->{' Ascender'},
	Descent	    => $self->{' Descender'},
	CapHeight   => $self->{' CapHeight'},
	StemV       => 0,
	#FontFile3  => "",
    });
}

sub cid_font_dictionary {
    my ($self) = @_;

    # CIDFont dictionary (Table 117)
    my $cid_font = BuildObj(++$objct, {
	Type => "/Font",
	Subtype => "/CIDFontType0",
	BaseFont => "/".$self->{internalname},
	CIDSystemInfo => $self->{' CIDSystemInfo'},
	# FontDescriptor => $self->font_descriptor,
    });

    if (my $p = GetObj($cid_font)) {
	if ($self->{vertical}) {
	    my $w2 = $self->w2_array;
	    if ($w2 && @$w2) {
		$p->{DW2} = $self->{' DW2'};
		$p->{W2} = $w2;
	    }
	} else {
	    my $w = $self->w_array;
	    if ($w && @$w) {
		$p->{DW} = $self->{' DW'};
		$p->{W} = $w;
	    }
	}
    }

    $cid_font;
}


sub tounicode_cmap {
    my ($self) = @_;

    my $cmaptype = 2;
    my $cmapname = "/".$self->{' CMapName'};
    my $cidsysteminfo = $self->{' CIDSystemInfo'};

    my $sub = $self->SUB;
    my $cid2uni = $prefer_utf16
	? sub { ($_[0]->[PSNAME] => $_[0]->[UNICODE]) }
	: sub { ($_[0]->[PSNAME] => decode "UTF16-BE", pack "n*", map hex($_), split '_', $_[0]->[UNICODE]) };
    my $code = { map { &$cid2uni($_) } grep defined $_->[UNICODE], @$sub };
    return undef unless %$code;

    my $ucmap = BuildObj(++$objct, {
	"Type" => "/CMap",
	"CMapName" => $cmapname,
	"CIDSystemInfo" => $cidsysteminfo,
    });
    $obj[$objct]->{STREAM} = join "\n",
	#grep !/^[%]/,
	split /\n/, <<endstream;
/CIDInit /ProcSet findresource begin
12 dict begin
begincmap
/CMapName $cmapname def
/CMapType $cmaptype def
/CIDSystemInfo
<< /Registry ($cidsysteminfo->{Registry})
    /Ordering ($cidsysteminfo->{Ordering})
    /Supplement $cidsysteminfo->{Supplement}
>> def
@{[ codespacerange([ map pack("U*", $_), keys %{$code} ]) ]}
@{[ bfrange($code) ]}
endcmap
CMapName currentdict /CMap defineresource pop
end
end
endstream
    $obj[$objct]->{DATA}{Length} = length $obj[$objct]->{STREAM};

    $ucmap;
}


sub subset {
    my ($self, @cid) = @_;
    return undef unless @cid;
    @cid = @{$cid[0]} if @cid == 1 && ref $cid[0] eq 'ARRAY';
    my $subset;
    if ($options & PYFTSUBSET) {
	my ($fh, $sub_font) = tempfile(DIR => '/tmp', CLEANUP => 1, SUFFIX => '.otf');
	my ($gh, $gid_file) = tempfile(DIR => '/tmp', CLEANUP => 1, SUFFIX => '.txt');
	print $gh join(',', @cid), "\n";
	close $gh;
	my @pyftsubset = (
	    "pyftsubset", $self->{fontfile}, # $PATH_otf,
	    "--output-file=$sub_font",
	    "--gids-file=$gid_file",
	    '--notdef-glyph',
	    #'--recommended-glyphs',
	);
	Notice("# @pyftsubset") if $debug; # xxxxx
	my $rc = system @pyftsubset;
	if ($?) {
	    ;
	} elsif (my $otf = Font::TTF::Font->open($sub_font)) {
	    $subset = $otf->{'CFF '};
	}
    } else {
	my $cff = $self->{' OTF'}->{'CFF '};
	if ($cff->can("subset")) {
	    $cff->notdef_glyph(1);
	    $subset = $cff->subset(@cid);
	}
    }
    return $subset->as_string if $subset;
    #Die("$0: can't subset $self->{internalname} ($self->{name})");
    return undef;
}

sub SUB {
    my ($self) = @_;

    return $self->{SUB} if defined $self->{SUB};

    my $sub;
    if (($options & CMAPFULL) == 0) {
	if ($self->{' embed'} || $embedall) {
	    $sub = $self->{SUB};
	} else {
	    my $name = join '-',
		$self->{' CIDSystemInfo'}{Registry} =~ /^\((.*?)\)$/,
		$self->{' CIDSystemInfo'}{Ordering} =~ /^\((.*?)\)$/,
		$self->{' CIDSystemInfo'}{Supplement};
	    if ($Predefined_CMap_names && $name =~ /$Predefined_CMap_names/) {
		$sub = [ grep $_->[OPTGSUB], @{$self->{SUB}} ];
	    } else {
		$sub = $self->{SUB};
	    }
	}
    } else {
	$sub = $self->{SUB};
    }

    $self->{SUB} = $sub;
}


# the font has the space glyph. (It's usually cid #1.)
sub has_space {
    my ($self) = @_;
    return defined $self->{NAM}->{space}->[PSNAME] &&
	$self->{NAM}->{space}->[PSNAME] == 1 &&
	exists $self->{spacewidth} && $self->{spacewidth} > 0;
}


# space using whitespace (for testing the USESPACE option)
sub psspace {
    my ($self, $n) = @_;
    $n //= 1;
    if ($n > 0) {
	confess "cidfont is required" unless defined $self->cidfont;
	my ($chf, $ch) = $self->GetNAM('space');
	return "<" . sprintf("%04X", $chf->[PSNAME]) x $n . ">";
    } else {
	return ();
    }
}


# text strings in the TJ array
sub pschar {
    my ($self, $c) = @_;

    confess "cidfont is required" unless defined $self->cidfont;

    return undef unless defined($c->[CHR]);
    return sprintf "<%04X>", $c->[CHF]->[PSNAME];
}


# text position
sub placement {
    my ($self, $c) = @_;

    confess "cidfont is required" unless defined $self->cidfont;

    return undef unless defined($c->[CHR]);

    if (my $gpos = $self->{' GPOS'}) {
	my $placement;
	my $gid = $self->{' CID2GID'}->[$c->[CHF]->[PSNAME]];
	if ($self->{vertical}) {
	    if (my $v = $gpos->{$gid}) {
		for ($v->{YPlacement}) {
		    $placement += $_ if defined;
		}
	    }
	} else {
	    if (my $v = $gpos->{$gid}) {
		for ($v->{XPlacement}) {
		    $placement += $_ if defined;
		}
	    }
	}
	return $placement;
    }

    return undef;
}


sub GetNAM {
    #my ($f, $c) = (@_);
    my ($self, $c) = (@_);
    my $f = $self;
    my $r = $f->{NAM}->{$c};

    unless ($r->[UNICODE]) {

        if (length $c == 1) {
            $r->[UNICODE] = sprintf "%04X", ord($c);
        }

	# converts decomposed char codes to composed char codes, and
	# verify they are defined in the font.  uses composed character
	# codes if verified.
        elsif (my ($hex) = $c =~ /^u([\dA-F_]{4,})$/) {
            my $u8 = pack "U*", map hex($_), split '_', $hex;
            if ($u8 !~ /\p{InCJK_Compatibility_Ideographs}/) {
                if (__PACKAGE__->can('NFC')) {
		    my $hex_2 = join '_', map { sprintf "%04X", $_ } unpack "n*",
			encode "UTF16-BE", NFC($u8);
		    $hex = $hex_2 if $f->{NAM}->{'u'.$hex_2} == $r;
                }
            }
            $r->[UNICODE] = $hex;
        }

        $r->[WIDTH]   //= 1000;
        $r->[CHRCODE] //= -1;
        $r->[PSNAME]  //= 0;

        if ($debug) {
            my $unicode = $r->[UNICODE] // 'undef';
            my $entity_name = $r->[PSNAME] // 'undef';
	    if ($entity_name && $f->cidfont) {
		$entity_name = sprintf "#%d", $entity_name;
	    }
            $stream .= "%!!! GetNAM: $f->{name}, $c, U+$unicode, $entity_name\n";
        }
    }
    return ($r, $c) if ref($r) eq 'ARRAY';
    return ($f->{NAM}->{$r}, $r);
}

sub AssignGlyph {
    my ($self, $chf, $ch) = (@_);

    return if $chf && defined $chf->[MINOR];

    ($chf->[MINOR], $chf->[MAJOR]) = ($self->{ALLOC}++, 0);
    push @{$self->{SUB}}, $chf;

    push(@{$self->{CHARSET}->[$chf->[MAJOR]]}, $chf->[PSNAME]);
    push(@{$self->{TRFCHAR}->[$chf->[MAJOR]]}, $ch);

    $stream .= "% Assign: $chf->[PSNAME] to $chf->[MAJOR]/$chf->[MINOR]\n" if $debug;
}

sub w_array {
    my ($self) = @_;

    my @w;
    my $n = 0;
    my $lastc = -1;
    for my $chf (sort { $a->[PSNAME] <=> $b->[PSNAME] } @{$self->{SUB}}) {
	my $c = $chf->[PSNAME];	# cid
	my $w = $chf->[WIDTH] // $self->{' DW'};
	if ($w == $self->{' DW'}) {
	    $n++;
	    next;
	}
	if (@w && $lastc + 1 == $c && $n == 0) {
	    if (ref $w[-1] eq 'ARRAY') {
		push @{$w[-1]}, $w;
		$lastc = $c;
		next;
	    }
	}
	push @w, $c, [ $w ];
	$lastc = $c;
	$n = 0;
    }

    if (1) {
	my $thresh = 4;
	my @w2 = ();
	my @t = ();
	while (my ($c, $list) = splice @w, 0, 2) {
	    @t = ($c, [shift @$list]);
	    while (defined (my $w = shift @$list)) {
		$c++;
		if (@t == 3) {
		    if ($t[2] == $w) {
			$t[1] = $c;
		    } else {
			push @w2, @t;
			@t = ($c, [ $w ]);
		    }
		} elsif (@t == 2) {
		    my $cons = 1;
		    for (1 .. $thresh) {
			$cons = 0, last unless @{$t[1]} >= $_ && $t[1]->[-$_] == $w;
		    }
		    if ($cons) {
			pop @{$t[1]} for 1 .. $thresh;
			push @w2, @t if @{$t[1]} > 0;
			@t = ($c - $thresh, $c, $w);
		    } else {
			push @{$t[1]}, $w;
		    }
		} else {
		    die "program error: t = ", str_w(\@t);
		}
	    }
	    push @w2, @t;
	    @t = ();
	}
	push @w2, @t;
	@w = @w2;
    }

    \@w;
}


sub w2_array {
    my ($self) = @_;

    my @w2;
    my $lastc = -1;
    for my $chf (sort { $a->[PSNAME] <=> $b->[PSNAME] } @{$self->{SUB}}) {
	my $c = $chf->[PSNAME];	# cid
	my $w = $chf->[WIDTH] // $self->{' DW'};

	# PDF 32000-1:2008 PP.271-272
	# The default position vector and vertical displacement vector shall be
	# specified by the DW2 entry in the CIDFont dictionary. DW2 shall be an
	# array of two values: the vertical component of the position vector v
	# and the vertical component of the displacement vector w1 (see Figure
	# 40). The horizontal component of the position vector shall be half the
	# glyph width, and that of the displacement vector shall be 0.
	#
	# EXAMPLE 2	If the DW2 entry is
	#    /DW2 [ 880 −1000 ]
	# then a glyph’s position vector and vertical displacement vector are
	#    v = (w0 ÷ 2, 880)
	#   w1 = (0, –1000)
	# where w0 is the width (horizontal displacement) for the same glyph.

	# w0 = (1000, 0)
	# w1 = (0, -1000)
	# v  = (c.width / 2 - 0,  c.height + c.descender) = (500, 880)
	# dw2 = (v.y, w1.y) = (880, -1000)

	my ($w1_x, $w1_y, $v_x, $v_y) = (
	    0,			  # w1_x
	    $self->{' DW2'}[1],	  # w1_y
	    $self->{' DW'} / 2,	  # v_x
	    $self->{' DW2'}[0]	  # v_y
	);

	if ($self->{vertical}) {
	    $w1_y = -$w;
	} else {
	    Die(join ' ', "can't happen near line ", __LINE__, " in ", __FILE__);
	    $w1_x = $w;
	}

	if (!ref $w2[-1] && @w2 >= 4 && $w2[-3] == $w1_y && $w2[-2] == $v_x && $w2[-1] == $v_y) {
	    $w2[-4] = $c;
	    $lastc = $c;
	    next;
	}

	if ($lastc + 1 == $c && ref $w2[-1] eq 'ARRAY') {
	    push @{$w2[-1]}, $w1_y, $v_x, $v_y;
	    $lastc = $c;
	    next;
	}

	push @w2, $c, [ $w1_y, $v_x, $v_y ];
	$lastc = $c;
    }

    \@w2;
}


sub bfrange {
    my ($bfchar) = @_;
    my $chunksize = 100;
    my @bfrange;
    my @bfchar;

    my @k = sort { $a <=> $b } keys %{$bfchar};
    while (@k > 0) {
	my $i = 0;
	while ($i + 1 <= $#k) {
	    last if $k[$i] + 1 != $k[$i + 1];
	    my ($a, $b);
	    if ($prefer_utf16) {
		$a = [ map hex($_), split '_', $bfchar->{$k[$i]} ];
		$b = [ map hex($_), split '_', $bfchar->{$k[$i + 1]} ];
	    } else {
		$a = [ map ord($_), split //, $bfchar->{$k[$i]} ];
		$b = [ map ord($_), split //, $bfchar->{$k[$i + 1]} ];
	    }
	    my $j = $#{$a};
	    last if $#{$a} != $#{$b};
	    last if $a->[$j] + 1 != $b->[$j];
	    1 while (--$j >= 0 && $a->[$j] == $b->[$j]);
	    last if $j >= 0;
	    $i++;
	}
	if ($i > 0) {
	    my @t = splice @k, 0, $i + 1;
	    push @bfrange, [ $t[0], $t[-1] ];
	} elsif ($i <= $#k) {
	    push @bfchar, shift @k;
	    $i++;
	}
    }

    join "\n", (
	blocking('bfrange', map {
	    my @hex;
	    if ($prefer_utf16) {
		@hex = split '_', $bfchar->{$_->[0]};
	    } else {
		@hex = map sprintf('%04X', $_), unpack 'n*',
		    encode 'UTF16-BE', $bfchar->{$_->[0]};
	    }
	    join ' ',
		sprintf("<%04X>", $_->[0]),
		sprintf("<%04X>", $_->[1]), "<@hex>";
	} @bfrange),
	blocking('bfchar', map {
	    my @hex;
	    if ($prefer_utf16) {
		@hex = split '_', $bfchar->{$_};
	    } else {
		@hex = map sprintf("%04X", $_), unpack "n*",
		    encode "UTF16-BE", $bfchar->{$_};
	    }
	    join ' ', sprintf("<%04X>", $_), "<@hex>";
	} @bfchar),
    );
}


sub codespacerange {
    my ($code) = @_;
    my @list;
    my %seen;
    for (sort grep !$seen{$_}++, @$code) {
	if (@list) {
	    if (length $list[-1]->[0] == length) {
		my @s = $list[-1]->[0] =~ /^(.*?)(.|\n)$/;
		my @x = /^(.*?)(.|\n)$/;
		if ($x[0] eq $s[0]) {
		    $list[-1]->[1] = $_;
		    next;
		}
	    }
	}
	if (@list) {
	    my @s = unpack 'n*', encode 'UTF16-BE', $list[-1]->[0];
	    my @e = unpack 'n*', encode 'UTF16-BE', $list[-1]->[1];
	    my @n = unpack 'n*', encode 'UTF16-BE', $_;
	    if ($e[0] == $n[0]) {
		Notice(join ' ', 'codespacerange:',
		    "<@{[ map sprintf('%04X', $_), @e ]}>",
		    'and',
		    "<@{[ map sprintf('%04X', $_), @n ]}>",
		    'overlapped');
	    }
	}
	push @list, [ $_, $_ ];
    }
    blocking('codespacerange', map {
	my @s = map sprintf("%04X", $_), unpack 'n*', encode 'UTF16-BE', $_->[0];
	my @e = map sprintf("%04X", $_), unpack 'n*', encode 'UTF16-BE', $_->[1];
	"<@s> <@e>";
    } @list);
}


sub cidrange {
    my ($tounicode) = @_;
    my @list;
    for (sort { $tounicode->{$a} cmp $tounicode->{$b} } keys %{$tounicode}) {
	if (@list) {
	    if (length $list[-1]->[0] == length $tounicode->{$_}) {
		my @s = $list[-1]->[0] =~ /^(.*?)(.|\n)$/;
		my @x = $tounicode->{$_} =~ /^(.*?)(.|\n)$/;
		if ($x[0] eq $s[0] && $list[-1]->[2] + (ord($x[1]) - ord($s[1])) == $_) {
		    $list[-1]->[1] = $tounicode->{$_};
		    next;
		}
	    }
	}
	push @list, [ $tounicode->{$_}, $tounicode->{$_}, $_ ];
    }
    join "\n", (
	blocking('cidrange', map {
	    my @s = map sprintf("%04X", $_), unpack 'n*', encode 'UTF16-BE', $_->[0];
	    my @e = map sprintf("%04X", $_), unpack 'n*', encode 'UTF16-BE', $_->[1];
	    join ' ', "<@s>", "<@e>", $_->[2];
	} grep $_->[0] ne $_->[1], @list),
	blocking('cidchar', map {
	    my @s = map sprintf("%04X", $_), unpack 'n*', encode 'UTF16-BE', $_->[0];
	    "<@s> $_->[2]";
	} grep $_->[0] eq $_->[1], @list),
    );
}


sub blocking {
    my ($name, @in) = @_;
    my $size = 100;
    my @out = ();
    while (@in) {
	my $n = min($size, scalar @in);
	push @out, "$n begin${name}";
	push @out, splice @in, 0, $n;
	push @out, "end${name}";
    }
    join "\n", @out;
}


sub parse_cmap {
    my ($tounicode, $cmap) = @_;
    $cmap =~ s/^\s*%.*//gm;
    my $hex = qr/[\da-f]+/i;
    while ($cmap =~ s/\d+\s+beginbf(range|char)\s*(.*?)\s*endbf\1\s*//s) {
	my ($t, $bf) = ($1, $2);
	while ($bf =~ s/^\s*<\s*($hex)\s*>\s*//s) {
	    my ($start, $end) = (hex $1, undef);
	    $end = hex $1 if $t eq 'range' && $bf =~ s/^\s*<\s*($hex)\s*>\s*//s;
	    $end //= $start;
	    my $value = '';
	    $value = $1 || $2 if $bf =~ s/^(?:\[\s*([^\]]+)\]|(\<[^\>]+\>|\S+))\s*//s;
	    #$value =~ s/<((?:$hex|\s)+)>/my $h = $1; $h =~ s{\s}{}g; "<$h>"/eg;
	    $value =~ s/<((?:$hex|\s)+)>/my $h = $1; $h =~ s{\s}{}g; $h/eg;
	    my @value = split /\s+/, $value;
	    for ($start .. $end) {
		last unless @value;
		#$tounicode->[$_] = shift @value;
		$tounicode->{$_} = shift @value;
	    }
	}
    }
}


sub gsub {
    my $otf = shift;

    my $gsub;
    for my $index (grep defined, @_) {
        my $value = $otf->{GSUB}{LOOKUP}[$index];
        if ($value->{TYPE} == 1) {
            for (@{$value->{SUB}}) {
                while (my ($gid, $i) = each %{$_->{COVERAGE}{val}}) {
                    $gsub->{$gid} = $_->{RULES}[$i][0]{ACTION}[0];
                }
            }
        }
        elsif ($value->{TYPE} == 4) {
            for (@{$value->{SUB}}) {
                while (my ($gid, $i) = each %{$_->{COVERAGE}{val}}) {
                    for (@{$_->{RULES}[$i]}) {
                        $gsub->{join $;, @{$_->{ACTION}}} =
                          [$gid + 0, @{$_->{MATCH}}];
                    }
                }
            }
        }
        else {
            die "gsub: unknown \$value->{TYPE}: $value->{TYPE}";
        }
    }
    $gsub;
}

sub gpos {
    my $otf = shift;

    my $gpos;
    for my $index (grep defined, @_) {
        my $value = $otf->{GPOS}{LOOKUP}[$index];

        if ($value->{TYPE} == 1) {

            # Lookup type 1 subtable: single adjustment positioning

            for (@{$value->{SUB}}) {
                while (my ($gid, $i) = each %{$_->{COVERAGE}{val}}) {
                    for (@{$_->{RULES}[$i]}) {
                        for (@{$_->{ACTION}}) {
                            while (my ($k, $v) = each %$_) {
                                $gpos->{$gid}{$k} = $v;
                            }
                        }
                    }
                }
            }

        }
        elsif ($value->{TYPE} == 2) {

            # Lookup type 2 subtable: pair adjustment positioning

            my $sub_index = 0;
            for (@{$value->{SUB}}) {

                my @gid;
                while (my ($gid, $i) = each %{$_->{COVERAGE}{val}}) {
                    $gid[$i] = $gid;
                }

                my $MATCH_TYPE  = $_->{MATCH_TYPE};
                my $ACTION_TYPE = $_->{ACTION_TYPE};

                if ($MATCH_TYPE eq 'g' && $ACTION_TYPE eq 'p') {

                    my $PairSetCount = @{$_->{RULES}};
                    for my $i (0 .. $PairSetCount - 1) {
                        my $PairValueCount = @{$_->{RULES}[$i]};
                        for my $j (0 .. $PairValueCount - 1) {
                            my $gid2 = $_->{RULES}[$i][$j]{MATCH}[0];
                            $gpos->{$gid[$i], $gid2} =
                              $_->{RULES}[$i][$j]{ACTION}[0];
                        }
                    }

                }
                elsif ($MATCH_TYPE eq 'c' && $ACTION_TYPE eq 'p') {

                    # $_->{FORMAT} = 2: Pair adjustment positioning
                    # format 2: class pair adjustment

                    # MATCH_TYPE = 'c': An array of class values
                    # ACTION_TYPE = 'p': Pair adjustment

                    for my $gid (@gid) {
                        my $c = $_->{CLASS}{val}{$gid};
                        next unless defined $c;
                        while (my ($gid2, $c2) = each %{$_->{MATCH}[0]{val}}) {
                            next unless $c2;
                            $gpos->{$gid, $gid2} =
                              $_->{RULES}[$c][$c2]{ACTION}[0];
                        }
                    }

                }
                else {
                    die "gpos: unknown \$_->{FORMAT}: $_->{FORMAT} in TYPE 2";
                }

            }

        }
        else {
            die "gpos: unknown \$value->{TYPE}: $value->{TYPE}";
        }
    }

    $gpos;
}

sub InCJK_Compatibility_Ideographs {
    join '',
      map { sprintf "%04X\t%04X\n", $_->[0], $_->[1] }
      grep_charblocks(qr/CJK Compatibility Ideographs/);
}

sub grep_charblocks {
    grep { $_->[2] =~ /$_[0]/ }
      sort { $a->[0] <=> $b->[0] }
      map  { @$_ } values %{charblocks()},
      [[0x3099, 0x309A, "Combining Katakana-Hiragana Voiced Sound Marks"],];
}

1;

# Local Variables:
# fill-column: 72
# mode: CPerl
# End:
# vim: set cindent noexpandtab shiftwidth=4 softtabstop=4 textwidth=72:
