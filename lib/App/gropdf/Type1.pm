package App::gropdf::Type1;

use strict;
use warnings;
require 5.8.0;
#use 5.008001;
use Carp;
use File::Path;

use App::gropdf::Base qw(:all);

my %StdEnc = (
    32  => 'space',
    33  => '!',
    34  => 'dq',
    35  => 'sh',
    36  => 'Do',
    37  => '%',
    38  => '&',
    39  => 'cq',
    40  => '(',
    41  => ')',
    42  => '*',
    43  => '+',
    44  => ',',
    45  => 'hy',
    46  => '.',
    47  => 'sl',
    48  => '0',
    49  => '1',
    50  => '2',
    51  => '3',
    52  => '4',
    53  => '5',
    54  => '6',
    55  => '7',
    56  => '8',
    57  => '9',
    58  => ':',
    59  => ';',
    60  => '<',
    61  => '=',
    62  => '>',
    63  => '?',
    64  => 'at',
    65  => 'A',
    66  => 'B',
    67  => 'C',
    68  => 'D',
    69  => 'E',
    70  => 'F',
    71  => 'G',
    72  => 'H',
    73  => 'I',
    74  => 'J',
    75  => 'K',
    76  => 'L',
    77  => 'M',
    78  => 'N',
    79  => 'O',
    80  => 'P',
    81  => 'Q',
    82  => 'R',
    83  => 'S',
    84  => 'T',
    85  => 'U',
    86  => 'V',
    87  => 'W',
    88  => 'X',
    89  => 'Y',
    90  => 'Z',
    91  => 'lB',
    92  => 'rs',
    93  => 'rB',
    94  => 'ha',
    95  => '_',
    96  => 'oq',
    97  => 'a',
    98  => 'b',
    99  => 'c',
    100 => 'd',
    101 => 'e',
    102 => 'f',
    103 => 'g',
    104 => 'h',
    105 => 'i',
    106 => 'j',
    107 => 'k',
    108 => 'l',
    109 => 'm',
    110 => 'n',
    111 => 'o',
    112 => 'p',
    113 => 'q',
    114 => 'r',
    115 => 's',
    116 => 't',
    117 => 'u',
    118 => 'v',
    119 => 'w',
    120 => 'x',
    121 => 'y',
    122 => 'z',
    123 => 'lC',
    124 => 'ba',
    125 => 'rC',
    126 => 'ti',
    161 => 'r!',
    162 => 'ct',
    163 => 'Po',
    164 => 'f/',
    165 => 'Ye',
    166 => 'Fn',
    167 => 'sc',
    168 => 'Cs',
    169 => 'aq',
    170 => 'lq',
    171 => 'Fo',
    172 => 'fo',
    173 => 'fc',
    174 => 'fi',
    175 => 'fl',
    177 => 'en',
    178 => 'dg',
    179 => 'dd',
    180 => 'pc',
    182 => 'ps',
    183 => 'bu',
    184 => 'bq',
    185 => 'Bq',
    186 => 'rq',
    187 => 'Fc',
    188 => 'u2026',
    189 => '%0',
    191 => 'r?',
    193 => 'ga',
    194 => 'aa',
    195 => 'a^',
    196 => 'a~',
    197 => 'a-',
    198 => 'ab',
    199 => 'a.',
    200 => 'ad',
    202 => 'ao',
    203 => 'ac',
    205 => 'a"',
    206 => 'ho',
    207 => 'ah',
    208 => 'em',
    225 => 'AE',
    227 => 'Of',
    232 => '/L',
    233 => '/O',
    234 => 'OE',
    235 => 'Om',
    241 => 'ae',
    245 => '.i',
    248 => '/l',
    249 => '/o',
    250 => 'oe',
    251 => 'ss',
);

my $gotinline=0;

my $rc = eval
{
    require Inline;
    my $inline;
    $inline=$ENV{XDG_CACHE_HOME} if exists($ENV{XDG_CACHE_HOME});
    $inline=$ENV{HOME}."/.cache/gropdf" if !$inline and exists($ENV{HOME});
    $inline=$ENV{PERL_INLINE_DIRECTORY} if exists($ENV{PERL_INLINE_DIRECTORY});
    mkpath($inline) if $inline;
    Inline->import (C => Config => DIRECTORY => $inline) if $inline;
    Inline->import (C =><<'EOC');

    static const uint32_t MAGIC1 = 52845;
    static const uint32_t MAGIC2 = 22719;

    typedef unsigned char byte;

    char* decrypt_exec_C(char *s, int len)
    {
        static uint16_t er=55665;
        byte clr=0;
        int i;
        er=55665;

        for (i=0; i < len; i++)
        {
            byte cypher = s[i];
            clr = (byte)(cypher ^ (er >> 8));
            er = (uint16_t)((cypher + er) * MAGIC1 + MAGIC2);
            s[i] = clr;
        }

        return(s);
    }

EOC
};

if($rc)
{
    $gotinline=1;
}

use Class::Tiny qw( fontno fnt
		    lenIV sec glyphused subrused glyphseen newsub term
		    bl seac ND NP RD );

sub new {
    my $class = shift;
    my $self = bless { @_ }, $class;
    $self->init;
    $self;
}

sub init {
    my ($self) = @_;

    confess "set fontno" unless defined $self->fontno;

    $self->{' Encoding'} = $self->{encoding} // 'CustomEnc';
    $self->{' CMapName'} = join '-', 'Adobe', 'Identity', 'UCS';
    #$self->{' CMapName'} = join '-', $self->{name}, 'Identity', 'UCS';

    my $fixwid = -1;
    for my $code (0 .. 255) {
	next unless defined(my $name = $self->{NO}[$code]);
	next unless defined(my $v    = $self->{NAM}{$name});
	if (ref $v && defined $v->[WIDTH]) {
	    $fixwid = $v->[WIDTH] if $fixwid == -1;
	    $fixwid = -2, last
		if $fixwid > 0 and $v->[WIDTH] != $fixwid;
	}
    }

    my $capheight = -1;
    for my $name ('A' .. 'Z') {
	next unless defined(my $v = $self->{NAM}{$name});
	if (ref $v && defined $v->[RST]) {
	    $capheight = $v->[RST] if $v->[RST] > $capheight;
	}
    }

    my $ascent = 0;
    for my $code (32 .. 127) {
	next unless defined(my $name = $self->{NO}[$code]);
	next unless defined(my $v    = $self->{NAM}{$name});
	if (ref $v && defined $v->[RST]) {
	    $ascent = $v->[RST] if $v->[RST] > $ascent;
	}
    }

    my @fntbbox = (0, 0, 0, 0);
    for my $code (0 .. 255) {
	next unless defined(my $name = $self->{NO}[$code]);
	next unless defined(my $v    = $self->{NAM}{$name});
	if (ref $v && defined $v->[WIDTH]) {
	    $fntbbox[1] = -$v->[RSB]
		if defined($v->[RSB])
		and -$v->[RSB] < $fntbbox[1];
	    $fntbbox[2] = $v->[WIDTH]
		if defined($v->[WIDTH])
		and $v->[WIDTH] > $fntbbox[2];
	    $fntbbox[3] = $v->[RST]
		if defined($v->[RST])
		and $v->[RST] > $fntbbox[3];
	}
    }

    $self->{fntbbox}   = \@fntbbox;
    $self->{ascent}    = $ascent;
    $self->{capheight} = $capheight;

    my $t1flags = 0;
    $t1flags |= 2**0 if $fixwid > -1;
    $t1flags |= (exists($self->{'special'})) ? 2**2 : 2**5;
    $t1flags |= 2**6 if $self->{slant} != 0;
    $self->{t1flags} = $t1flags;

    # my ($head,$body,$tail) = GetType1($download{$fontkey});
    # $head =~ s/\/Encoding .*?readonly def\b/\/Encoding StandardEncoding def/s;
    # $fontlst{$fontno}->{HEAD} = $head;
    # $fontlst{$fontno}->{BODY} = $body;
    # $fontlst{$fontno}->{TAIL} = $tail;
    # $fno = ++$objct;
    # EmbedFont($fontno, \%fnt);

    $self->sec({});
    $self->glyphused([]);
    $self->subrused([ '#0', '#1', '#2', '#3', '#4' ]);
    $self->glyphseen({});	# not used
    $self->newsub(4);
    $self->term("\n");
    $self->bl([]);
    $self->seac({});

    $self->ND('ND');
    $self->NP('NP');
    $self->RD('RD');

    Notice( "\nFont '$self->{internalname} ($self->{name})' has $self->{lastchr} glyphs\n"
          . "You would see a noticeable speedup if you install the perl module Inline::C\n"
    ) if !$gotinline and $self->{lastchr} > 1000;

    $self;
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

    my ($head, $body, $tail);
    if (exists($self->{fontfile}) && ($self->{embed} || $embedall)) {
	if (!($options & NOFILE)) {
	    $self->{FONTFILE} = BuildObj(
		++$objct,
		{
		    'Length1' => 0,
		    'Length2' => 0,
		    'Length3' => 0
		});
	}
	($head, $body, $tail) = $self->GetType1; #($self->{fontfile});
    }

    my @objno = ();
    my $chars = $self->{TRFCHAR};
    for (my $j = 0; $j <= $#{$chars}; $j++) {
	my @differ;
	my $firstch;
	my $lastch = 0;
	my @widths;
	my $miss = -1;

	my $CharSet = join('', @{$self->{CHARSET}->[$j]});
	push(@{$chars->[$j]}, 'space') if $j == 0 and $self->{NAM}->{space}->[PSNAME];

	my $nam = $self->{NAM};
	foreach my $og (sort { $nam->{$a}->[MINOR] <=> $nam->{$b}->[MINOR] } (@{$chars->[$j]})) {
	    my $g = $og;
	    while (defined $g) {
		my ($glyph, $trf) = $self->GetNAM($g);
		my $chrno = $glyph->[MINOR];
		$firstch = $chrno if !defined($firstch);
		$lastch  = $chrno;
		$widths[$chrno - $firstch] = $glyph->[WIDTH];

		push(@differ, $chrno) if $chrno > $miss;
		$miss = $chrno + 1;
		my $ps = $glyph->[PSNAME];
		push(@differ, $ps);

		if (exists($self->seac->{$trf})) {
		    $g = pop(@{$self->seac->{$ps}});
		    $CharSet .= $g if $g;
		}
		else {
		    $g = undef;
		}
	    }
	}

	foreach my $w (@widths) { $w = 0 if !defined($w); }

	my $fontnm = $self->fontno . (($j) ? ".$j" : '');
	$self->{FirstChar}   = $firstch;
	$self->{LastChar}    = $lastch;
	$self->{Differences} = \@differ;
	$self->{Widths}      = \@widths;
	$self->{CharSet}     = $CharSet;
	$self->{ToUnicode}   = $textenccmap if $j == 0 and $CharSet =~ m'/minus';

	my $fj = $fontlst{$fontnm};
	$fj->{OBJ} = BuildObj(
	    ++$objct,
	    {
		'Type'      => '/Font',
		'Subtype'   => '/Type1',
		'BaseFont'  => '/' . $self->{internalname},
		map +($_ => $self->{$_}), grep defined $self->{$_},
		qw( Widths FirstChar LastChar ToUnicode ),
	    }
	);
	GetObj($fj->{OBJ})->{Encoding} = BuildObj(
	    ++$objct,
	    {
		'Type'        => '/Encoding',
		'Differences' => $self->{Differences}
	    }
	);
	GetObj($fj->{OBJ})->{FontDescriptor} = BuildObj(
	    ++$objct,
	    {
		'Type'        => '/FontDescriptor',
		'FontName'    => '/' . $self->{internalname},
		'Flags'       => $self->{t1flags},
		'FontBBox'    => $self->{fntbbox},
		'ItalicAngle' => $self->{slant},
		'Ascent'      => $self->{ascent},
		'Descent'     => $self->{fntbbox}->[1],
		'CapHeight'   => $self->{capheight},
		'StemV'       => 0,
		'CharSet'     => "($self->{CharSet})",
	    }
	);

	$fj->{OBJNO} = GetOno($fj->{OBJ}); # $objct
	push @objno, $fj->{OBJNO};

	$fj->{NM} = '/F' . $fontnm;
	$pages->{'Resources'}->{'Font'}->{'F' . $fontnm} = $fj->{OBJ};

	# $fj->{FNT} = $self;
	# $obj[$objct]->{STREAM} = $t1stream;
    }

    if (exists($self->{fontfile}) && ($self->{embed} || $embedall)) {
	if ($options & SUBSET and !($options & NOFILE)) {
	    if (defined($self->term)) {
		$body = $self->encrypt($self->bl);
	    }
	}
	if (my $FontFile = $self->{FONTFILE}) {
	    my $i = GetOno($FontFile);
	    $obj[$i]->{STREAM} = $head . $body . $tail;
	    $obj[$i]->{DATA}->{Length1} = length($head);
	    $obj[$i]->{DATA}->{Length2} = length($body);
	    $obj[$i]->{DATA}->{Length3} = length($tail);
	    foreach my $ono (@objno) {
		my $p = GetObj($ono);
		my $d = GetObj($p->{FontDescriptor});
		$d->{FontFile} = $FontFile if !($options & NOFILE);
		if ($options & SUBSET) {
		    my $nm = '/' . SubTag() . $self->{internalname};
		    $d->{FontName} = $nm;
		    $p->{BaseFont} = $nm;
		}
	    }
	}
    }

}


sub GetNAM {
    my ($self, $c) = (@_);
    my $f = $self;		# xxxxx
    my $r = $f->{NAM}->{$c};
    return ($r, $c) if ref($r) eq 'ARRAY';
    return ($f->{NAM}->{$r}, $r);
}


sub AssignGlyph {
    my ($self, $chf, $ch) = (@_);

    if ($chf->[CHRCODE] > 32 and $chf->[CHRCODE] < 128) {
        ($chf->[MINOR], $chf->[MAJOR]) = ($chf->[CHRCODE], 0);
    }
    elsif (defined($chf->[UNICODE]) and $chf->[UNICODE] eq "2212")    # minus
    {
        ($chf->[MINOR], $chf->[MAJOR]) = (31, 0);
    }
    else {
        ($chf->[MINOR], $chf->[MAJOR]) = $self->NextAlloc; #($self);
    }

    # Add ToUnicode CMap entry - requires change to afmtodit
    push(@{$self->{CHARSET}->[$chf->[MAJOR]]}, $chf->[PSNAME]);
    push(@{$self->{TRFCHAR}->[$chf->[MAJOR]]}, $ch);

    $stream .= "% Assign: $chf->[PSNAME] to $chf->[MAJOR]/$chf->[MINOR]\n" if $debug;
}


sub NextAlloc {
    my $self = shift;

    my $alloc = ++$self->{ALLOC};

    my $maj = $alloc >> 8;
    my $min = $alloc & 0xff;

    my $start = ($maj == 0) ? 128 : 33;
    $min = $start if $min < $start;
    $min++ if $min == ord('(');
    $min++ if $min == ord(')');
    $maj++, $min = $start if $min > 255;

    $self->{ALLOC} = ($maj << 8) + $min;

    return ($min, $maj);
}


sub GetType1 {
    my $self = shift;
    #my $file = shift;
    my $file = $self->{fontfile};

    my ($l1,   $l2,   $l3);      # Return lengths
    my ($head, $body, $tail);    # Font contents
    my $f;

    OpenFile(\$f, $fontdir, $file);
    Die("cannot open font '$file' for embedding") if !defined($f);

    $head = GetChunk($f, 1, "currentfile eexec", $file);

    Die("'$file' not an Adobe Type 1 font") if $head !~ m/^%!PS-AdobeFont-1.0:/;
    Die("font format for '$file' not recognised: font header missing") if eof($f);

    $body = GetChunk($f, 2, "00000000",    $file);
    $tail = GetChunk($f, 3, "cleartomark", $file);

    #$body=GetChunk($f,2,"00000000",$file) if !eof($f);
    #$tail=GetChunk($f,3,"cleartomark",$file) if !eof($f);

    $head =~ s/\/Encoding \d.*?readonly def\b/\/Encoding StandardEncoding def/s;

    $self->lenIV(4);
    if ($options & SUBSET) {
	$self->lenIV($1) if $head =~ m'/lenIV\s+(\d+)';
	decrypt_exec(\$body);
	$body = substr($body, $self->lenIV);
	$body =~ m/begin([\r\n]+)/;
	$self->term($1);
	if (defined($self->term)) {
	    $self->bl([ split($self->term, $body) ]);
	    $self->map_subrs($self->bl);
	    $self->Subset($self->bl, $self->glyphs);
	}
	else {
	    Warn("Unable to parse font '$self->{internalname}' for subsetting");
	}
    }

    return ($head, $body, $tail);
}

sub GetChunk {
    my $F       = shift;
    my $segno   = shift;
    my $ascterm = shift;
    my $file    = shift;
    my ($type, $hdr, $chunk);
    binmode($F);
    my $enc = "ascii";

    while (1) {

        # There may be multiple chunks of the same type

        my $ct = read($F, $hdr, 2);

        if ($ct == 2) {
            if (substr($hdr, 0, 1) eq "\x80") {

                # binary chunk

                my $chunktype = ord(substr($hdr, 1, 1));
                $enc = "binary";

                if (defined($type) and $type != $chunktype) {
                    seek($F, -2, 1);
                    last;
                }

                $type = $chunktype;
                return if $chunktype == 3;

                $ct = read($F, $hdr, 4);
                Die("font format for '$file' not recognised: ".
		    "failed to read binary segment length") if $ct != 4;
                my $sl = unpack('V', $hdr);
                my $data;
                my $chk = read($F, $data, $sl);
                Die("font format for '$file' not recognised: ".
		    "failed to read binary segment") if $chk != $sl;
                $chunk .= $data;
            }
            else {
                # ascii chunk

                my $hex = 0;
                seek($F, -2, 1);
                my $ct = 0;

                while (1) {
                    my $lin = <$F>;

                    last if !$lin;

                    $hex = 1, $enc .= " hex"
                      if $segno == 2
                      and !$ct
                      and $lin =~ m/^[A-F0-9a-f]{4,4}/;

                    if ($segno != 2 and $lin =~ m/^(.*$ascterm[\n\r]?)(.*)/) {
                        $chunk .= $1;
                        seek($F, -length($2) - 1, 1) if $2;
                        last;
                    }
                    elsif ($segno == 2 and $lin =~ m/^(.*?)($ascterm.*)/) {
                        $chunk .= $1;
                        seek($F, -length($2) - 1, 1) if $2;
                        last;
                    }

                    chomp($lin), $lin = pack('H*', $lin) if $hex;
                    $chunk .= $lin;
                    $ct++;
                }

                last;
            }
        }
        else {
            Die("font format for '$file' not recognised: failed to read 2 header bytes");
        }
    }

    return $chunk;
}


sub decrypt_char {
    my $self = shift;

    my $l = shift;
    my (@la) = unpack('C*', $l);
    my @res;

    if ($self->lenIV >= 0) {
        my $clr;
        my $cr   = C_DEF;
        my $skip = $self->lenIV;

        foreach my $cypher (@la) {
            $clr = ($cypher ^ ($cr >> 8)) & 0xFF;
            $cr  = (($cypher + $cr) * MAGIC1 + MAGIC2) & 0xFFFF;
            push(@res, $clr) if --$skip < 0;
        }

        return (\@res);
    }
    else {
        return (\@la);
    }
}


sub decrypt_exec {
    my ($rbody) = @_;
    if ($gotinline) {
	decrypt_exec_C($$rbody, length($$rbody));
    } else {
	decrypt_exec_P($rbody, length($$rbody));
    }
}

sub decrypt_exec_P {
    my $e = shift;
    my $l = shift;
    $l--;
    my $clr;
    my $er = E_DEF;

    foreach my $j (0 .. $l) {
        my $cypher = ord(substr($$e, $j, 1));
        $clr = ($cypher ^ ($er >> 8)) & 0xFF;
        $er  = (($cypher + $er) * MAGIC1 + MAGIC2) & 0xFFFF;
        substr($$e, $j, 1) = chr($clr);
    }

    return ($e);
}


sub map_subrs {
    my $self = shift;
    my $lines = shift;
    my $stage = 0;
    my $lin   = $lines->[0];
    my $i     = 0;
    my ($RDre, $NDre);

    for (my $j = 0 ; $j <= $#{$lines} ; $lin = $lines->[++$j]) {

        #	next if !defined($lines->[$j]);

        if ($stage == 0) {
            if ($lin =~ m/^\s*\/Subrs \d+/) {
                $self->sec->{'#Subrs'} = $j;
                $stage = 1;
                #$RDre = qr/\Q$RD\E/;
                #$NDre = qr/\Q$ND\E/;
                $RDre = quotemeta($self->RD);
                $NDre = quotemeta($self->ND);
            }
            elsif ($lin =~
m/^\/(.+?)\s*\{string currentfile exch readstring pop\}\s*executeonly def/
              )
            {
                $self->RD($1);
            }
            elsif ($lin =~ m/^\/(.+?)\s*\{noaccess def\}\s*executeonly def/) {
                $self->ND($1);
            }
            elsif ($lin =~ m/^\/(.+?)\s*\{noaccess put\}\s*executeonly def/) {
                $self->NP($1);
            }
            elsif ($lin =~ m'^/lenIV\s+(\d+)') {
                $self->lenIV($1);
            }
        }
        elsif ($stage == 1) {
            if ($lin =~ m/^\s*\d index \/CharStrings \d+/) {
                $self->sec->{'#CharStrings'} = $j;
                $stage               = 2;
                $i                   = 0;
            }
            elsif ($lin =~ m/^\s*dup\s+(\d+)\s+(\d+)\s+$RDre (.*)/s) {
                my $n = $1;
                my $l = $2;
                my $s = $3;

                if (!exists($self->sec->{"#$n"})) {
                    $self->sec->{"#$n"} = [$j, {}];
                    $i = $j;
                    $self->sec->{"#$n"}->[NEWNO] = $n if $n <= $self->newsub;
                }

                if (length($s) > $l) {
                    $s = substr($s, 0, $l);
                }
                else {
                    $lin .= $self->term . $lines->[++$j];
                    $lines->[$j] = undef;
                    redo;
                }

                # $s = decrypt_char($s);
                # subs_call($s,"#$n");
                $lines->[$i] = ["#$n", $l, $s, $self->NP];
            }
            elsif ($lin =~ m/^$NDre/) { }
            else {
                Warn("Don't understand '$lin'");
            }
        }
        elsif ($stage == 2) {
            if ($lin =~ m/^0{64}/) {
                $self->sec->{'#Pad'} = $j;
                $stage = 3;
            }
            elsif ($lin =~ m/^\s*\/([-.\w]*)\s+(\d+)\s+$RDre (.*)/s) {
                my $n = $1;
                my $l = $2;
                my $s = $3;

                $self->sec->{"/$n"} = [$j, {}] if !exists($self->sec->{"/$n"});

                if (length($s) > $l) {
                    $s = substr($s, 0, $l);
                }
                else {
                    $lin .= $self->term . $lines->[++$j];
                    $lines->[$j] = undef;
                    $i--;
                    redo;
                }

                $i += $j;

                if ($self->sec->{"/$n"}->[0] != $i) {

                    # duplicate glyph name !!! discard ???
                    $lines->[$i] = undef;
                }
                else {
                    $lines->[$i] = ["/$n", $l, $s, $self->ND];
                }

                $i = 0;
            }

            # else
            # {
            #     Warn("Don't understand '$lin'");
            # }
        }
        elsif ($stage == 3) {
            if ($lin =~ m/cleartomark/) {
                $self->sec->{'#cleartomark'} = [$j];
                $stage = 4;
            }
            elsif ($lin !~ m/^0+$/) {
                Warn("Expecting padding - got '$lin'");
            }
        }
    }
}

sub subs_call {
    my $self = shift;
    my $charstr = shift;
    my $key     = shift;
    my $lines   = shift;
    my @c;

    for (my $j = 0 ; $j <= $#{$charstr} ; $j++) {
        my $n = $charstr->[$j];

        if ($n >= 32 and $n <= 246) {
            push(@c, [$n - 139, 1]);
        }
        elsif ($n >= 247 and $n <= 250) {
            push(@c, [(($n - 247) << 8) + $charstr->[++$j] + 108, 1]);
        }
        elsif ($n >= 251 and $n <= 254) {
            push(@c, [-(($n - 251) << 8) - $charstr->[++$j] - 108, 1]);
        }
        elsif ($n == 255) {
            $n =
              ($charstr->[++$j] << 24) +
              ($charstr->[++$j] << 16) +
              ($charstr->[++$j] << 8) +
              $charstr->[++$j];
            $n =~ $n if $n & 0x8000;
            push(@c, [$n, 1]);
        }
        elsif ($n == 10) {
            if ($c[$#c]->[1]) {
                $c[$#c]->[0] = $self->MarkSub("#$c[$#c]->[0]");
                $c[$#c - 1]->[0] = $self->MarkSub("#$c[$#c-1]->[0]")
                  if ($c[$#c]->[0] == 4 and $c[$#c - 1]->[1]);
            }
            push(@c, [10, 0]);
        }
        elsif ($n == 12) {
            push(@c, [12, 0]);
            my $n2 = $charstr->[++$j];
            push(@c, [$n2, 0]);

            if ($n2 == 16)    # callothersub
            {
                $c[$#c - 4]->[0] = $self->MarkSub("#$c[$#c-4]->[0]")
                  if ($c[$#c - 4]->[1]);
            }
            elsif ($n2 == 6)    # seac
            {
                my $ch = $StdEnc{$c[$#c - 2]->[0]};
                my $chf;

                # if ($ch ne 'space')
                {
                    ($chf) = $self->GetNAM($ch);

                    if (!defined($chf->[MINOR])) {
                        $self->AssignGlyph($chf, $ch);
                        $self->Subset($lines, $chf->[PSNAME]);
                        push(@{$self->seac->{$key}}, "$ch");
                    }
                }

                $ch = $StdEnc{$c[$#c - 3]->[0]};

                if ($ch ne 'space') {
                    ($chf) = $self->GetNAM($ch);

                    if (!defined($chf->[MINOR])) {
                        $self->AssignGlyph($chf, $ch);
                        $self->Subset($lines, $chf->[PSNAME]);
                        push(@{$self->seac->{$key}}, "$ch");
                    }
                }
            }
        }
        else {
            push(@c, [$n, 0]);
        }
    }

    $self->sec->{$key}->[CHARCHAR] = \@c;

    # foreach my $j (@c) {Warn("Undefined op in $key") if !defined($j);}
}

sub Subset {
    my $self = shift;

    my $lines  = shift;
    my $glyphs = shift;
    my $extra  = shift;

    foreach my $g ($glyphs =~ m/(\/[.\w-]+)/g) {
	#confess "'/ ' in glyphs" if $g eq '/ ';
        if (exists($self->sec->{$g})) {
	    #$self->glyphseen->{$g} = 1;
	    #$g = '/space' if $g eq '/ '; # not used

            my $ln = $lines->[$self->sec->{$g}->[LINE]];
            $self->subs_call($self->sec->{$g}->[CHARCHAR] = $self->decrypt_char($ln->[STR]),
                $g, $lines);

            push(@{$self->glyphused}, $g);
        }
        else {
            Warn("Can't locate glyph '$g' in font") if $g ne '/space';
        }
    }
}

sub MarkSub {
    my $self = shift;
    my $k = shift;

    if (exists($self->sec->{$k})) {
        if (!defined($self->sec->{$k}->[NEWNO])) {
            $self->sec->{$k}->[NEWNO] = $self->newsub($self->newsub + 1);
            push(@{$self->subrused}, $k);

            my $ln = $self->bl->[$self->sec->{$k}->[LINE]];
            $self->subs_call($self->sec->{$k}->[CHARCHAR] =
			     $self->decrypt_char($ln->[STR]), $k, $self->bl);
        }

        return ($self->sec->{$k}->[NEWNO]);
    }
    else {
        Warn("Missing Subrs '$k'");
    }
}

sub encrypt {
    my $self = shift;
    my $lines = shift;

    if (exists($self->sec->{'#Subrs'})) {
	my $n = $self->newsub($self->newsub + 1);
        $lines->[$self->sec->{'#Subrs'}] =~ s/\d+\s+array/$n array/;
    }
    else {
        Warn("Unable to locate /Subrs");
    }

    if (exists($self->sec->{'#CharStrings'})) {
        my $n = $#{$self->glyphused} + 1;
        $lines->[$self->sec->{'#CharStrings'}] =~ s/\d+\s+dict /$n dict /;
    }
    else {
        Warn("Unable to locate /CharStrings");
    }

    my $bdy;

    for (my $j = 0 ; $j <= $#{$lines} ; $j++) {
        my $lin = $lines->[$j];

        next if !defined($lin);

        if (ref($lin) eq 'ARRAY' and $lin->[TYPE] eq $self->NP) {
            foreach my $sub (@{$self->subrused}) {
                if (exists($self->sec->{$sub})) {
                    $self->subs_call(
                        $self->sec->{$sub}->[CHARCHAR] =
                          $self->decrypt_char($lines->[$self->sec->{$sub}->[LINE]]->[STR]),
                        $sub, $lines
                    ) if (!defined($self->sec->{$sub}->[CHARCHAR]));
                    my $cs = $self->encode_charstr($self->sec->{$sub}->[CHARCHAR], $sub);
                    $bdy .= join ' ', "dup", $self->sec->{$sub}->[NEWNO],
			length($cs), $self->RD, $cs, $self->NP;
                    $bdy .= "\n";
                }
                else {
                    Warn("Failed to locate Subr '$sub'");
                }
            }

            while (!defined($lines->[$j + 1])
                or ref($lines->[$j + 1]) eq 'ARRAY')
            {
                $j++;
            }
        }
        elsif (ref($lin) eq 'ARRAY' and $lin->[TYPE] eq $self->ND) {
            foreach my $chr (@{$self->glyphused}) {
                if (exists($self->sec->{$chr})) {
                    my $cs = $self->encode_charstr($self->sec->{$chr}->[CHARCHAR], $chr);
                    $bdy .= join ' ', $chr, length($cs), $self->RD, $cs, $self->ND;
                    $bdy .= "\n";
                }
                else {
                    Warn("Failed to locate glyph '$chr'");
                }
            }

            while (!defined($lines->[$j + 1])
                or ref($lines->[$j + 1]) eq 'ARRAY')
            {
                $j++;
            }
        }
        else {
            $bdy .= "$lin\n";
        }
    }

    my @bdy = unpack('C*', $bdy);
    return (encrypt_exec(\@bdy));
}

sub encrypt_exec {
    my $la = shift;
    unshift(@{$la}, 0x44, 0x65, 0x72, 0x69);
    my $res;
    my $cypher;
    my $er = E_DEF;

    foreach my $clr (@{$la}) {
        $cypher = ($clr ^ ($er >> 8)) & 0xFF;
        $er     = (($cypher + $er) * MAGIC1 + MAGIC2) & 0xFFFF;
        $res .= pack('C', $cypher);
    }

    return ($res);
}

sub encode_charstr {
    my $self = shift;
    my $ops = shift;
    my $key = shift;
    my @c;

    foreach my $c (@{$ops}) {
        my $n   = $c->[0];
        my $num = $c->[1];

        if ($num) {
            if ($n >= -107 and $n <= 107) {
                push(@c, $n + 139);
            }
            elsif ($n >= 108 and $n <= 1131) {
                my $hi = ($n - 108) >> 8;
                my $lo = ($n - 108) & 0xff;
                push(@c, $hi + 247, $lo);
            }
            elsif ($n <= -108 and $n >= -1131) {
                my $hi = abs($n + 108) >> 8;
                my $lo = abs($n + 108) & 0xff;
                push(@c, $hi + 251, $lo);
            }

            # elsif ($n >= -32768 and $n <= 32767)
            # {
            #     push(@c,28,($n>>8) & 0xff,$n & 0xff);
            # }
            else {
                push(@c,
                    255,
                    ($n >> 24) & 0xff,
                    ($n >> 16) & 0xff,
                    ($n >> 8) & 0xff,
                    $n & 0xff);
            }
        }
        else {
            push(@c, $n);
        }
    }

    return ($self->encrypt_char(\@c));
}

sub encrypt_char {
    my $self = shift;
    my $la = shift;
    unshift(@{$la}, 0x44, 0x65, 0x72, 0x69) if $self->lenIV;
    my $res;
    my $cypher;
    my $cr = C_DEF;

    foreach my $clr (@{$la}) {
        $cypher = ($clr ^ ($cr >> 8)) & 0xFF;
        $cr     = (($cypher + $cr) * MAGIC1 + MAGIC2) & 0xFFFF;
        $res .= pack('C', $cypher);
    }

    return ($res);
}


1;

# Local Variables:
# fill-column: 72
# mode: CPerl
# End:
# vim: set cindent noexpandtab shiftwidth=4 softtabstop=4 textwidth=72:
