use 5.008001;
use strict;
package Parse::CPAN::Meta;
# ABSTRACT: Parse META.yml and META.json CPAN metadata files
# VERSION

use Exporter;
use Carp 'croak';

our @ISA = qw/Exporter/;
our @EXPORT_OK = qw/Load LoadFile JSON_BACKEND YAML_BACKEND/;

sub load_file {
  my ($class, $filename) = @_;

  my $meta = _slurp($filename);

  if ($filename =~ /\.ya?ml$/) {
    return $class->load_yaml_string($meta);
  }
  elsif ($filename =~ /\.json$/) {
    return $class->load_json_string($meta);
  }
  else {
    $class->load_string($meta); # try to detect yaml/json
  }
}

sub load_string {
  my ($class, $string) = @_;
  if ( $string =~ /^---/ ) { # looks like YAML
    return $class->load_yaml_string($string);
  }
  elsif ( $string =~ /^\s*\{/ ) { # looks like JSON
    return $class->load_json_string($string);
  }
  else { # maybe doc-marker-free YAML
    return $class->load_yaml_string($string);
  }
}

sub load_yaml_string {
  #my ($class, $string) = @_;
  #YAML_BACKEND not folded, since YAML_BACKEND doesn't exist yet
  my $data = eval { no strict 'refs'; &{YAML_BACKEND()."\::Load"}($_[1]) };
  croak $@ if $@;
  return $data || {}; # in case document was valid but empty
}

sub load_json_string {
  #my ($class, $string) = @_;
  #JSON_BACKEND not folded, since JSON_BACKEND doesn't exist yet
  my $data = eval { JSON_BACKEND()->new->decode($_[1]) };
  croak $@ if $@;
  return $data || {};
}

sub yaml_backend {
  if (! defined $ENV{PERL_YAML_BACKEND} ) {
    _can_load( 'CPAN::Meta::YAML', 0.011 )
      or croak "CPAN::Meta::YAML 0.011 is not available\n";
    return "CPAN::Meta::YAML";
  }
  else {
    my $backend = $ENV{PERL_YAML_BACKEND};
    _can_load( $backend )
      or croak "Could not load PERL_YAML_BACKEND '$backend'\n";
    $backend->can("Load")
      or croak "PERL_YAML_BACKEND '$backend' does not implement Load()\n";
    return $backend;
  }
}

sub json_backend {
  if (! $ENV{PERL_JSON_BACKEND} or $ENV{PERL_JSON_BACKEND} eq 'JSON::PP') {
    _can_load( 'JSON::PP' => 2.27103 )
      or croak "JSON::PP 2.27103 is not available\n";
    return 'JSON::PP';
  }
  else {
    _can_load( 'JSON' => 2.5 )
      or croak  "JSON 2.5 is required for " .
                "\$ENV{PERL_JSON_BACKEND} = '$ENV{PERL_JSON_BACKEND}'\n";
    return "JSON";
  }
}

sub _slurp {
  require Encode;
  open my $fh, "<:raw", "$_[0]" ## no critic
    or die "can't open $_[0] for reading: $!";
  my $content = do { local $/; <$fh> };
  $content = Encode::decode('UTF-8', $content, Encode::PERLQQ());
  return $content;
}
  
sub _can_load {
  my ($module, $version) = @_;
  (my $file = $module) =~ s{::}{/}g;
  $file .= ".pm";
  return 1 if $INC{$file};
  return 0 if exists $INC{$file}; # prior load failed
  eval {
    require $file;
    $module->VERSION($version) if defined $version;
    1;
  } or return 0;
  return 1;
}

# Kept for backwards compatibility only
# Create an object from a file
sub LoadFile ($) {
  return Load(_slurp(shift));
}

# Parse a document from a string.
sub Load ($) {
  require CPAN::Meta::YAML;
  my $object = eval { CPAN::Meta::YAML::Load(shift) };
  croak $@ if $@;
  return $object;
}

require constant;
constant->import({
    'JSON_BACKEND' => Parse::CPAN::Meta->json_backend(),
    'YAML_BACKEND' => Parse::CPAN::Meta->yaml_backend()
});

1;

__END__

=pod

=for Pod::Coverage

=head1 SYNOPSIS

    #############################################
    # In your file
    
    ---
    name: My-Distribution
    version: 1.23
    resources:
      homepage: "http://example.com/dist/My-Distribution"
    
    
    #############################################
    # In your program
    
    use Parse::CPAN::Meta;
    
    my $distmeta = Parse::CPAN::Meta->load_file('META.yml');
    
    # Reading properties
    my $name     = $distmeta->{name};
    my $version  = $distmeta->{version};
    my $homepage = $distmeta->{resources}{homepage};

=head1 DESCRIPTION

B<Parse::CPAN::Meta> is a parser for F<META.json> and F<META.yml> files, using
L<JSON::PP> and/or L<CPAN::Meta::YAML>.

B<Parse::CPAN::Meta> provides three methods: C<load_file>, C<load_json_string>,
and C<load_yaml_string>.  These will read and deserialize CPAN metafiles, and
are described below in detail.

B<Parse::CPAN::Meta> provides a legacy API of only two functions,
based on the YAML functions of the same name. Wherever possible,
identical calling semantics are used.  These may only be used with YAML sources.

All error reporting is done with exceptions (die'ing).

Note that META files are expected to be in UTF-8 encoding, only.  When
converted string data, it must first be decoded from UTF-8.

=head1 METHODS

=head2 load_file

  my $metadata_structure = Parse::CPAN::Meta->load_file('META.json');

  my $metadata_structure = Parse::CPAN::Meta->load_file('META.yml');

This method will read the named file and deserialize it to a data structure,
determining whether it should be JSON or YAML based on the filename.
The file will be read using the ":utf8" IO layer.

=head2 load_yaml_string

  my $metadata_structure = Parse::CPAN::Meta->load_yaml_string($yaml_string);

This method deserializes the given string of YAML and returns the first
document in it.  (CPAN metadata files should always have only one document.)
If the source was UTF-8 encoded, the string must be decoded before calling
C<load_yaml_string>.

=head2 load_json_string

  my $metadata_structure = Parse::CPAN::Meta->load_json_string($json_string);

This method deserializes the given string of JSON and the result.  
If the source was UTF-8 encoded, the string must be decoded before calling
C<load_json_string>.

=head2 load_string

  my $metadata_structure = Parse::CPAN::Meta->load_string($some_string);

If you don't know whether a string contains YAML or JSON data, this method
will use some heuristics and guess.  If it can't tell, it assumes YAML.

=head2 YAML_BACKEND
=head2 yaml_backend

  use Parse::CPAN::Meta qw( YAML_BACKEND );
  my $data = &{YAML_BACKEND."\::Load"}($filebuffer);
  #deprecated
  my $backend = Parse::CPAN::Meta->yaml_backend;

Returns the module name of the YAML serializer. Use the upper case exported
const version for performance. See L</ENVIRONMENT> for details.

=head2 JSON_BACKEND
=head2 json_backend

  use Parse::CPAN::Meta qw( JSON_BACKEND );
  my $obj = JSON_BACKEND->new();
  #deprecated
  my $backend = Parse::CPAN::Meta->json_backend;

Returns the module name of the JSON serializer.  This will either
be L<JSON::PP> or L<JSON>.  Even if C<PERL_JSON_BACKEND> is set,
this will return L<JSON> as further delegation is handled by
the L<JSON> module.  The upper case exported const version decides once on
startup which module to use. Use it for performance reasons.
See L</ENVIRONMENT> for details.

=head1 FUNCTIONS

For maintenance clarity, no functions are exported by default.  These functions
are available for backwards compatibility only and are best avoided in favor of
C<load_file>.

=head2 Load

  my @yaml = Parse::CPAN::Meta::Load( $string );

Parses a string containing a valid YAML stream into a list of Perl data
structures.

=head2 LoadFile

  my @yaml = Parse::CPAN::Meta::LoadFile( 'META.yml' );

Reads the YAML stream from a file instead of a string.

=head1 ENVIRONMENT

=head2 PERL_JSON_BACKEND

By default, L<JSON::PP> will be used for deserializing JSON data. If the
C<PERL_JSON_BACKEND> environment variable exists, is true and is not
"JSON::PP", then the L<JSON> module (version 2.5 or greater) will be loaded and
used to interpret C<PERL_JSON_BACKEND>.  If L<JSON> is not installed or is too
old, an exception will be thrown.

=head2 PERL_YAML_BACKEND

By default, L<CPAN::Meta::YAML> will be used for deserializing YAML data. If
the C<PERL_YAML_BACKEND> environment variable is defined, then it is interpreted
as a module to use for deserialization.  The given module must be installed,
must load correctly and must implement the C<Load()> function or an exception
will be thrown.

=cut
