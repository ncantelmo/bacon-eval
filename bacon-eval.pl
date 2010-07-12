#!/usr/bin/perl -w
use strict;
use Cwd qw(realpath);

use Getopt::Long;
use Pod::Usage;



##=================================================================##
##
##  File:   bacon-eval.pl
##  Author: Nathan Cantelmo
##  Edited: July 11th, 2010
##  Notes:  Evaluation script for the proggit bacon_graph challenge
##          Takes a bacon_graph solution and sample directory and
##          runs the solution on each input file in the sample dir.
##
##  Arg 1:  Sample directory containing challenge input files
##  Arg 2:  Executable (bacon_graph solution) to evaluate
##
##=================================================================##


##=========================  Constants  ===========================##

use constant VERSION => "0.0.9";




##=========================   Globals   ===========================##

my %_samples  = ();     ## %_samples { "file_name" } -> { $score }

                        ## Config variables
my $_cfg_help = 0;      ##   - Print help message and exit
my $_cfg_vers = 0;      ##   - Print version and exit
my $_cfg_dir  = "";     ##   - Directory containing test input files
my $_cfg_bin  = "";     ##   - Binary (solution) to evaluate




##========================  Subroutines  ==========================##

sub version()
{
  print "Proggit challenge #4 solution evaluator v" . VERSION . "\n\n";
}



sub process_args()
{
  return GetOptions('h|help'      => \$_cfg_help,
                    'v|version'   => \$_cfg_vers);
}



sub load_samples()
{
  print "  Loading input samples...\n";

  my @fnames = glob("$_cfg_dir/*");  # Glob the sample fnames into an array

  # Then, iterate over each sample file
  foreach my $fname (sort(@fnames))
  {
    # Read in the next sample file into a hash
    my $sample = read_sample($fname) or die "Failed to load sample file '$fname'";
    
    # Then store the sample into the global sample hash
    $_samples{$fname} = $sample;     

    print "    Loaded sample: '$fname'\n";
  }

  print "  Loaded all sample files\n\n";
  return 1;
}



sub read_sample($)
{
  my $fname  = shift;
  my %sample = ();

  ## Open sample file
  if (!open(SAMPLE, "<$fname")) 
  { 
    print STDERR "$!\n"; 
    return 0; 
  }

  ## Read in header info
  my $header = <SAMPLE>;
  if ($header =~ /^\s*(\d+)x(\d+)\s+(\d+)\s*$/)
  {
    $sample{'n'} = $1;
    $sample{'m'} = $2;
    $sample{'b'} = $3;
    $sample{'p_map'} = ();
  }
  else
  {
    print STDERR "Encountered bad sample header line: '$_'\n";
    close(SAMPLE);
    return 0;
  }

  my $row = 0;

  ## Read in graph data
  while (<SAMPLE>)
  {
    if    ($_ =~ /^\s*$/)       { next; }            # Skip blank lines
    elsif ($_ =~ /^\s*\.+\s*$/) { $row++; next; }    # Skip rows w/out pop centers
    elsif ($_ =~ /^\s*([\.P]+)\s*$/)                 # Read all other graph rows
    {
      ## Make sure that we haven't read too many lines
      if ($row >= $sample{'n'})
      {
        print STDERR "Sample graph has too many rows\n";
        close(SAMPLE);
        return 0;
      }

      my $col = 0;
      my @points = split(//, $1);
      foreach my $pt (@points)
      {
        if ($pt eq 'P') { push(@{$sample{'p_map'}}, "$row,$col"); }
        $col++;
       
        # TODO: Should also check for bad column size, but I don't want to make this too slow for now
      }

      $row++;
    }
    else
    {
      print STDERR "Encountered bad sample graph line: $_\n";
      close(SAMPLE);
      return 0;
    }
  }

  ## Close sample file
  close(SAMPLE);

  ## Return sample object reference
  return \%sample;
}



## Manhattan distance
sub calc_distance_manhattan($$)
{
  my $a_txt = shift;
  my $b_txt = shift;

  my @a = split(/\,/, $a_txt);
  my @b = split(/\,/, $b_txt);

  return (abs($a[0] - $b[0]) + abs($a[1] - $b[1]));
}




sub min_distance($$)
{
  my $p     = shift;
  my $b_map = shift;

  my $min   = -1;

  ## Iterate over bacon dispensers
  foreach my $b (@{$b_map})
  {
    my $dis = calc_distance_manhattan($p, $b);

    if ($min < 0 || $dis < $min) { $min = $dis; }
    if ($min eq 1) { return 1; }  ## Exit early on the minimum possible distance
  }

  return $min;
}



sub generate_score($)
{
  my $sample = shift;
  my $score  = 0;

  ## Iterate over population centers
  foreach my $p (@{$sample->{'p_map'}})
  {
    ## Find the minimal distance from pop. center $p to a bacon dispenser 
    my $min = min_distance($p, $sample->{'b_map'});

    ## Complain and return early if something goes wrong
    if ($min < 0)
    {
      print STDERR "Warning: Min distance calculation failed\n";
      return -1;
    }

    ## Otherwise, add the result to the tally
    $score += $min;
  }

  return $score;  
}



sub eval_solution($$)
{
  my $fname   = shift;
  my $sample  = shift;

  my @eval_cmd = ( realpath($_cfg_bin), $fname );

  ## Execute @eval_cmd and store the output in $result
  my $result = `@eval_cmd`;

  ## Now parse the result lines
  my @res_lines = split(/\n/, $result);

  ## Storing the score from the first line
  $sample->{'app_score'} = shift(@res_lines);

  ## ...and the coordinates from the remaining lines
  my @res_map = ();

  foreach my $line (@res_lines)
  {
    if    ($line =~ /^\s*$/)              { next; }                ## Skip blank lines
    elsif ($line =~ /^\s*(\d+\,\d+)\s*$/) { push(@res_map, $1); }  ## Store good lines
    else                                                           ## Error on bad lines
    {
      print STDERR "Bad line encountered: $line\n";
      return -1;
    }
  }

  ## TODO: Check/complain here about wrong number of bacon dispensers
  ## TODO: Check/complain here about bacon dispensers on pop. centers

  ## Record the bacon dispenser map output by the eval command
  $sample->{'b_map'} = \@res_map;

  ## Generate a score based on the bacon dispenser map
  $sample->{'eval_score'} = generate_score($sample);

  return 0;
}



sub dump_sample($)
{
  my $sample = shift;

  print "         <n,m,b> -> <" . $sample->{'n'} . "," . $sample->{'m'} . "," . $sample->{'b'} . ">\n" .
        "          p_map  -> ";

  foreach my $p (@{$sample->{'p_map'}}) {  print "<$p> "; }
  print "\n";

  print "      eval_score -> " . $sample->{'eval_score'} . "\n" .
        "       app_score -> " . $sample->{'app_score'}      . "\n" .
        "           b_map -> ";

  foreach my $b (@{$sample->{'b_map'}}) {  print "<$b> "; }

  print "\n\n";
}



sub dump_results()
{
  print "  Results:\n";

  foreach my $fname (keys %_samples)
  {
    print "    sample: '$fname':\n";
    dump_sample($_samples{$fname});
  }

  print "\n";
}




##=========================    Setup    ===========================##

process_args() or pod2usage(2);

if ($_cfg_help) { pod2usage(1); }
if ($_cfg_vers) { version(); exit(0); }


## Make sure that the binary and sample dir were given
if (($#ARGV + 1) < 2)
{
  pod2usage({ -message => "Too few arguments given", -exitval => 2 });
}

## They exist, so treat them as config settings from here on out
$_cfg_dir = $ARGV[0];
$_cfg_bin = $ARGV[1]; 

## Make sure the binary and sample dir both exist
die "The evaluation binary '$_cfg_bin' does not exist" unless (-e $_cfg_bin);
die "The sample directory '$_cfg_dir' does not exist"  unless (-e $_cfg_dir);

## And make sure that the sample directory is actually a directory
die "The sample dir '$_cfg_dir' is not a directory!"   unless (-d $_cfg_dir); 




##=========================    Main    ============================##

version();
print "Evaluating solution '$_cfg_bin' with test dir '$_cfg_dir'...\n";

## First, read in the samples
load_samples() 
  or die "Failed to load samples from directory '$_cfg_dir'";

## Them for each input $fname in %_samples...
foreach my $fname (keys %_samples)
{
  my $sample = $_samples{$fname};

  ## Evaluate the solution against the sample and store the result
  eval_solution($fname, $sample);
}

## After we're done testing everything, output the results
dump_results();




##=========================    POD    =============================##   

__END__

=head1 NAME

bacon-eval.pl - Proggit challenge #4 sol'n evaluator

=head1 SYNOPSIS

bacon-eval.pl [options] <input_directory> <binary_to_run>

  Options:
    -h|--help		Print this message and exit
    -v|--version	Print the version number and exit

=cut
