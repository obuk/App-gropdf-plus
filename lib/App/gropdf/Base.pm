package App::gropdf::Base;

use strict;
use warnings;
require 5.8.0;
#use 5.008001;
use Carp;

our %cfg;

$cfg{GROFF_VERSION}='@VERSION@';
$cfg{GROFF_FONT_PATH}='@GROFF_FONT_DIR@';
$cfg{RT_SEP}='@RT_SEP@';

if ($cfg{RT_SEP} eq '@RT_SEP@') {
    $cfg{RT_SEP} = ':';
    $cfg{GROFF_VERSION} = '1.24.0';
    $cfg{GROFF_FONT_PATH} = join $cfg{RT_SEP},
	"$ENV{HOME}/share/groff/site-font",
	"$ENV{HOME}/share/groff/$cfg{GROFF_VERSION}/font",
	'/usr/lib/font';
}

my $constant;
BEGIN {
use constant $constant = {
    WIDTH    => 0,
    CHRCODE  => 1,
    PSNAME   => 2,
    MINOR    => 3,
    MAJOR    => 4,
    UNICODE  => 5,
    RST      => 6,
    RSB      => 7,
    GSUB     => 8,

    CHR      => 0,
    XPOS     => 1,
    CWID     => 2,
    HWID     => 3,
    NOMV     => 4,
    CHF      => 5,

    MAGIC1   => 52845,
    MAGIC2   => 22719,
    C_DEF    => 4330,
    E_DEF    => 55665,

    LINE     => 0,
    CALLS    => 1,
    NEWNO    => 2,
    CHARCHAR => 3,

    NUMBER   => 0,
    LENGTH   => 1,
    STR      => 2,
    TYPE     => 3,

    SUBSET   => 1,
    USESPACE => 2,
    COMPRESS => 4,
    NOFILE   => 8,

    PYFTSUBSET => 64,

    PI => 3.141592653589793,
};
}

our @obj;			# Array of PDF objects
our $objct = 0;			# Count of Objects
our %env;			# Current environment
our %fontlst;			# Fonts Loaded
our $pages;			# Pointer to /Pages object
our $stream = '';		# Current Text/Graphics stream
our $prog;

our @fdlist;
our $frot;
our $fpsz;
our $embedall  = 0;
our $debug     = 0;
our $want_help = 0;
our $version   = 0;
our $stats     = 0;
our $unicodemap;
our $options   = SUBSET + USESPACE + COMPRESS;
our $PDFver    = 1.7;
our @idirs;
our $xitcd     = 0;
our $warnexit  = 0;
our @Foundry;

our $textenccmap = '';		# CMap for groff text.enc encoding
our $fontdir;
our $devnm = 'devpdf';

use Exporter 'import';
our @EXPORT_OK = (
    keys %$constant,
    qw( %cfg $prog @obj $objct our %env %fontlst $pages $stream $xitcd
	$warnexit $options @fdlist @idirs $frot $fpsz $debug $want_help
	$PDFver $version $options $embedall @Foundry $stats $warnexit
	$unicodemap $textenccmap $fontdir $devnm BuildObj ),
    qw( GetObj GetOno OpenFile SubTag PI rad deg Notice Warn Die Msg ),
);
our %EXPORT_TAGS = (
    all => [ @EXPORT_OK ],
);

sub BuildObj {
    my $ono = shift;
    my $val = shift;

    $obj[$ono]->{DATA} = $val;

    return ("$ono 0 R ");
}

sub GetOno {
    confess "fatal program error (\$_[0] is undef)" unless defined $_[0];
    (split(' ', $_[0]))[0];
}

sub GetObj {
    $obj[GetOno($_[0])]->{DATA};
}

sub SubTag {
    my $res;

    foreach (1 .. 6) {
        $res .= chr(int((rand(26))) + 65);
    }

    return ($res . '+');
}

sub OpenFile {
    my $f    = shift;
    my $dirs = shift;
    my $fnm  = shift;

    if (substr($fnm, 0, 1) eq '/' or substr($fnm, 1, 1) eq ':')    # dos
    {
        return if -r "$fnm" and open($$f, "<$fnm");
    }

    my (@dirs) = split($cfg{RT_SEP}, $dirs);

    foreach my $dir (@dirs) {
        last if -r "$dir/$devnm/$fnm" and open($$f, "<$dir/$devnm/$fnm");
    }
}

sub rad {
    $_[0] * PI / 180
}

sub deg {
    return int($_[0] * 180 / PI);
}

sub Notice {
    unshift(@_, "notice: ");
    my $msg = join('', @_);
    Msg(0, $msg);
}

sub Warn {
    unshift(@_, "warning: ");
    my $msg = join('', @_);
    Msg(0, $msg);
    $xitcd = 1 if $warnexit;
}

sub Die {
    my $msg = join('', @_);
    Msg(1, $msg);
}

sub Msg {
    my ($fatal, $msg) = @_;

    print STDERR "$prog:";
    print STDERR "$env{SourceFile}:" if exists($env{SourceFile});
    print STDERR " ";
    print STDERR "fatal error: " if $fatal;
    print STDERR "$msg\n";
    exit 1 if $fatal;
}

1;

# Local Variables:
# fill-column: 72
# mode: CPerl
# End:
# vim: set cindent noexpandtab shiftwidth=4 softtabstop=4 textwidth=72:
