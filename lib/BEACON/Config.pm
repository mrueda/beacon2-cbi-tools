package Config;

use strict;
use warnings;
use autodie;
use feature    qw(say);
use List::Util qw(any);
use Sys::Hostname;
use File::Spec::Functions qw(catdir catfile updir);
use Cwd                   qw(realpath);
use Data::Dumper;
use YAML::XS qw(LoadFile DumpFile);

#$YAML::XS::QuoteNumericStrings = 0;

=head1 NAME

    BEACON::Config - Package for Config subroutines

=head1 SYNOPSIS

  use BEACON::Config

=head1 DESCRIPTION


=head1 AUTHOR

Written by Manuel Rueda, PhD

=cut

=head1 METHODS

=cut

=head2 read_config_file

    About   : Subroutine that reads the configuration file
    Usage   :            
    Args    :  

=cut

sub read_config_file {

    my $config_file = shift;

    # Load variables
    my $root_dir = realpath( catdir( $main::Bin, File::Spec->updir ) );    # Global $::Bin variable

    my $hostname = hostname;
    my $user     = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);

    # Definining options for config
    my $beacon_config =
      defined $config_file ? $config_file
      : ( $user eq 'mrueda'
          && ( $hostname eq 'mrueda-ws1' || $hostname eq 'mrueda-ws5' ) )
      ? catfile( $root_dir, 'bin', 'mrueda_ws1_config.yaml' )
      : catfile( $root_dir, 'bin', 'config.yaml' );

    # Ensure that all necessary configuration values are present
    my @required_keys = qw(
      hs37fasta hg19fasta hg38fasta hg19clinvar hg38clinvar hg19cosmic hg38cosmic hg19dbnsfp hg38dbnsfp snpeff snpsift bcftools mem tmpdir mongoimport mongostat mongodburi mongosh dbnsfpset
    );

    # Parsing config file
    my %config = parse_yaml_file( $beacon_config, \@required_keys );

    # Validating config
    validate_config( \%config, \@required_keys );

    # **** Important note about <hs37> *******
    # We loaded default values for hs37cosmic or hs37dbnsfp, which are good for development
    # but when <using beacon.config> the paths for hs37cosmic or hs37dbnsfp are not specified
    # so they're hard-coded below
    $config{hs37cosmic}  = $config{hg19cosmic};
    $config{hs37dbnsfp}  = $config{hg19dbnsfp};
    $config{hs37clinvar} = $config{hg19clinvar};

    #print Dumper \%config;
    #Check that DB exes/files and tmpdir exist
    while ( my ( $key, $val ) = each %config ) {
        next
          if ( $key eq 'mem' || $key eq 'dbnsfpset' || $key eq 'mongodburi' );
        die
"We could not find <$val> files\nPlease check for typos? in your <$beacon_config> file"
          unless -e $val;
    }

    # Below are a few internal paramaters
    my $beacon_bin = "$root_dir/lib/BEACON/bin";    # Global $::Bin variable
    my $java       = '/usr/bin/java';
    $config{snpeff}  = "$java -Xmx" . $config{mem} . " -jar $config{snpeff}";
    $config{snpsift} = "$java -Xmx" . $config{mem} . " -jar $config{snpsift}";
    $config{bash4bff}     = catfile( $beacon_bin, 'run_vcf2bff.sh' );
    $config{bash4html}    = catfile( $beacon_bin, 'run_bff2html.sh' );
    $config{bash4mongodb} = catfile( $beacon_bin, 'run_bff2mongodb.sh' );
    $config{vcf2bff}      = catfile( $beacon_bin, 'vcf2bff.pl' );
    $config{bff2json}     = catfile( $beacon_bin, 'bff2json.pl' );
    $config{json2html}    = catfile( $beacon_bin, 'bff2html.pl' );
    $config{browserdir}   = catdir( $root_dir, 'browser' );
    $config{assetsdir} =
      catdir( $root_dir, 'utils', 'bff_browser', 'static', 'assets' );

    # Ensure $config{paneldir} is defined or default to config{browserdir}/data
    $config{paneldir} //= catdir( $config{browserdir}, 'data' );

    # Check if the scripts exist and have +x permission
    my @scripts =
      qw(bash4bff bash4html bash4mongodb vcf2bff bff2json json2html);
    for my $script (@scripts) {
        die "You don't have +x permission for script <$config{$script}>"
          unless ( -x $config{$script} );
    }
    die "Sorry only [ega|all] values are accepted for <dbnsfpset>"
      unless ( $config{dbnsfpset} eq 'all' || $config{dbnsfpset} eq 'ega' );

    return wantarray ? %config : \%config;
}

=head2 read_param_file

    About   : Subroutine that reads the parameters file
    Usage   :            
    Args    : 

=cut

sub read_param_file {

    my $arg        = shift;               # Some args will be needed for QC
    my $param_file = $arg->{paramfile};

    # We load %param with the default values
    my %param = (
        bff       => {},
        center    => 'CRG',
        datasetid => 'default_beacon_1',
        ega       => {
            egac => 'EGAC00000000000',
            egad => 'EGAD00000000000',
            egas => 'EGAS00000000000',
        },
        genome     => 'hg19',
        organism   => 'Homo Sapiens',
        projectdir => 'beacon',
        bff2html   => 0,
        pipeline   => {
            vcf2bff     => 'false',
            bff2html    => 'false',
            bff2mongodb => 'false'
        },
        technology => 'Illumina HiSeq 2000'

    );
    my @keys = keys %param;

    # NOTE: Nested parameters overwrite all
    # For instance, only {bff}{metadatadir} will empty {bff}
    %param = ( %param, parse_yaml_file( $param_file, \@keys ) )
      if $param_file;    # merging two hashes in one
                         #print Dumper \%param and die;

    # Below are a few internal paramaters
    chomp( my $nthreadhost = qx{/usr/bin/nproc} ) // 1;
    $param{jobid} = time . substr( "00000$$", -5 );
    $param{date}  = localtime();

    # Override projectdir if an override argument is provided
    if ( defined $arg->{'projectdir-override'}
        && $arg->{'projectdir-override'} ne '' )
    {
        $param{projectdir} = $arg->{'projectdir-override'};
    }
    else {
        # Replace spaces with underscores and append job ID
        $param{projectdir} =~ tr/ /_/;
        $param{projectdir} .= '_' . $param{jobid};
    }
    $param{log}         = catfile( $param{projectdir}, 'log.json' );
    $param{hostname}    = hostname;
    $param{user}        = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
    $param{nthreadhost} = 0 + $nthreadhost;                              # coercing it to be a number
    $param{nthreadless} = $param{nthreadhost} > 1 ? $param{nthreadhost} - 1 : 1;
    my $str_nthreadless = $param{nthreadless};                           # We copy it (otherwise it will get "stringified" below and printed with "" in log.json)

    $param{zip} =
      ( -x '/usr/bin/pigz' )
      ? "/usr/bin/pigz -p $str_nthreadless"
      : '/bin/gzip';
    $param{organism} =
      $param{organism} eq lc('human') ? 'Homo Sapiens' : $param{organism};
    $param{gvvcfjson} =
      catfile( $param{projectdir}, 'vcf', 'genomicVariationsVcf.json.gz' );

    # Check parameter 'genome' (using any from List::Utils instead of exist $key{value}
    my @assemblies = qw(hg19 hg38 hs37);
    die "Please select a valid reference genome. The options are [@assemblies]"
      unless ( any { $_ eq $param{genome} } @assemblies );

    # Enforcing options depending on mode
    my ( $opt_a, $opt_b, $opt_c ) = ( 0, $param{bff2html}, 0 );
    if ( $arg->{mode} eq 'full' ) {
        ( $opt_a, $opt_c ) = ( 1, 1 );
    }
    elsif ( $arg->{mode} eq 'vcf' ) {
        ( $opt_a, $opt_c ) = ( 1, 0 );
    }
    else {    #mongodb
        ( $opt_a, $opt_b, $opt_c ) = ( 0, 0, 1 );
    }
    $param{pipeline}{vcf2bff}     = $opt_a;
    $param{pipeline}{bff2html}    = $opt_b;
    $param{pipeline}{bff2mongodb} = $opt_c;

    # Check if -f user_collections for modes [mongodb|full]
    if ( $arg->{mode} eq 'mongodb' || $arg->{mode} eq 'full' ) {
        my @collections =
          qw(runs cohorts biosamples individuals genomicVariations  analyses datasets);
        push @collections, 'genomicVariationsVcf' if $arg->{mode} eq 'mongodb';
        my @user_collections =
          grep { $_ ne 'metadatadir' } sort keys %{ $param{bff} };
        my $metadata_dir = $param{bff}{metadatadir};
        for my $collection (@user_collections) {
            die
"Collection: <$collection> is not a valid value for bff:\nAllowed values are <@collections>"
              unless any { $_ eq $collection } @collections;
            my $tmp_file =
                $collection eq 'genomicVariationsVcf'
              ? $param{bff}{$collection}
              : catfile( $metadata_dir, $param{bff}{$collection} );
            die
              "Collection: <$collection> does not have a valid file <$tmp_file>"
              unless -f $tmp_file;
            $param{bff}{$collection} = $tmp_file;
        }
    }

    # Force genomicVariations.json value if $mode eq 'full'
    $param{bff}{genomicVariationsVcf} = $param{gvvcfjson}
      if $arg->{mode} eq 'full';

    # Warn messages
    warn "Organism not tested => $param{organism}"
      if lc( $param{organism} ) ne 'homo sapiens';

    return wantarray ? %param : \%param;
}

sub parse_yaml_file {

    my $yaml_file = shift;

    # Keeping booleans as 'true' or 'false'. Perl still handles 0 and 1 internally.
    $YAML::XS::Boolean = 'JSON::PP';

    # Load YAML file into a Perl hash
    my $yaml = LoadFile($yaml_file);

    return wantarray ? %$yaml : $yaml;    # Return hash or hashref based on context
}

sub validate_config {

    my ( $config, $required_keys ) = @_;

    # Ensure required_keys is an array reference
    die "Required keys must be an array reference"
      unless ref $required_keys eq 'ARRAY';

    # Ensure all required keys are present in the configuration hash
    for my $key (@$required_keys) {
        die "Missing required parameter <$key> in the configuration file"
          unless exists $config->{$key};
    }

    return 1;    # Return true if validation passes
}
1;
