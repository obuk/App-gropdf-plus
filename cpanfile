# gropdf
requires 'perl', '5.8.0';
#requires 'perl', '5.008001';
requires 'Exporter::Easy';
requires 'File::Path';
requires 'File::Spec';
requires 'Getopt::Long';
requires 'POSIX';

# App::gropdf::OpenType
requires 'Carp';
requires 'Class::Tiny';
requires 'Encode';
requires 'File::Temp';
requires 'Font::TTF';
requires 'Font::TTF::Cmap::Uvs';
requires 'Font::TTF::CFF_';
requires 'List::Util';
#requires 'Perl::Tidy';
requires 'Unicode::Normalize';
requires 'Unicode::UCD';

on 'test' => sub {
    requires 'Test::More', '0.98';
};
