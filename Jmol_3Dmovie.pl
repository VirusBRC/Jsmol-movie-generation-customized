#!/usr/bin/perl

# This Perl script takes a Jmol state file, or a PDB 3D structure file,
# generates a movie that shows the rotation of the 3D structure around Y axis.
# It has an option to create a smoother (larger) file, and a regular sized file
# This script requires following programs:
# Jmol, a java-based structure-rendering program
# Xvfb, a virtual X server used to run programs on a server w/o physical display
# ffmpeg, to create movie from a series of still images. V0.6.5 is required, as
# V0.10.* has problem creating MP4 and avi movies.

# Author: G Sun, Vecna Technologies, Inc., May 15, 2012

# Input options: 
# 1. Jmol state file, default
# 2. PDB file, required if no Jmol state file
# 3. format (avi or mp4), default=mp4
# 4. file size, 6MB or 3MB, default=3MB

# Output:
# 1. movie file in avi or mp4 format
# 2. file to indicate the job is finished (?)

use strict;
use warnings;
use File::Spec::Functions;
use POSIX qw(strftime);

use English;
use Carp;
use Data::Dumper;
use File::Temp qw/ tempfile tempdir /;

# un-comment the following line or change the following line to the location of the modules
use lib ("/home/gsun/northrop/jmol");
use version; our $VERSION = qv('1.0');
use Getopt::Long;
use Start_Xvfb;

my $debug = 0;

############# Constants #############

# Program locations, may leave blank if the programs are accessible from the prompt
my $progs = {
        # Location of Jmol.jar,
        Jmol_jar => '',
        # Location of Xvfb executible, such as /usr/bin/Xvfb
        Xvfb => '',
        # Location of ffmpeg executible, such as ~/prog/ffmpeg/ffmpeg-0.10.2/ffmpeg
        ffmpeg => '',
};
$progs->{Jmol_jar} = '/home/gsun/prog/jmol/jmol-12.2.24/Jmol.jar' if(!$progs->{Jmol_jar});
$progs->{ffmpeg}   = '/home/gsun/prog/ffmpeg/ffmpeg-0.6.5/ffmpeg' if(!$progs->{ffmpeg});
# Version 0.10.3 has problem with MP4 and avi
#$progs->{ffmpeg}   = '/home/gsun/prog/ffmpeg/ffmpeg-0.10.3/ffmpeg' if(!$progs->{ffmpeg});


############# User-defined Options #############

# Get user-defined options
my $dir_path   = ''; # directory of PDB and state files, also for output
my $spt_state  = ''; # State script from Jmol, to set up the initial state
my $infile     = ''; # PDB file, mainly for debug
my $format_default = 'mp4'; # mp4 is default
my $format     = ''; # mp4 or avi
my $large_file = ''; # regular or large file size

my $exe_dir  = './';
my $exe_name = $0;
if ($exe_name =~ /^(.*[\/])([^\/]+[.]pl)$/i) {
    ($exe_dir, $exe_name) = ($1, $2);
} else {
    $exe_dir  = `pwd`;
}
print STDERR "$exe_name: $0 executing...\n";
print STDERR "$exe_name: command='$0 @ARGV'\n";
my $useropts = GetOptions(
                 "i=s"    => \$infile,    # Optional pdb file if no Jmol state file
                 "s=s"    => \$spt_state, # Jmol state file, preferred
                 "f=s"    => \$format,    # format of output, either avi or mp4(default)
                 "large_file" => \$large_file, # Large file=6MB, small file=3MB
                 );
if ($spt_state =~ /^(.*[\/])([^\/]+)$/i) {
    ($dir_path, $spt_state) = ($1,$2);
    print STDERR "$exe_name: \$dir_path='$dir_path' \$spt_state='$spt_state'\n";
} elsif ($infile =~ /^(.*[\/])([^\/]+)$/i) {
    ($dir_path, $infile) = ($1, $2);
    print STDERR "$exe_name: \$dir_path='$dir_path' \$infile='$infile'\n";
}

$dir_path = './' if (!$dir_path && ($spt_state || $infile));
$format = ($format =~ /avi/i) ? lc($format) : $format_default;
print STDERR "$exe_name: \$dir_path='$dir_path' \$spt_state=$spt_state \$infile='$infile'\n";
print STDERR "$exe_name: \$format='$format' \$large_file=$large_file\n";
print STDERR "$exe_name: \$format='$format' \$large_file=$large_file\n";
#$outfile = $dir_path.'/'.$outfile if ($dir_path && $outfile && $outfile !~ /[\/]/);
#print STDERR "$exe_name: \$outfile='$outfile'\n";


############# Main Program #############

    my $success = 0;
    my $errcode = '';

    # Change working directory to where input file is located
    my $pwd_old = `pwd`;
    chomp($pwd_old);
    $exe_dir = $pwd_old.'/'.$exe_dir if ($exe_dir !~ /^[\/]/i);
    if ($dir_path !~ /^[\/]/) {
        $dir_path = $pwd_old.'/'.$dir_path;
        $debug && print STDERR "$exe_name: changed to \$dir_path=$dir_path\n";
    } else {
        $debug && print STDERR "$exe_name: didn't need change \$dir_path=$dir_path\n";
    }
    $debug && print STDERR "$exe_name: \$dir_path=$dir_path\n";
    chdir($dir_path);
    $debug && print STDERR "$exe_name: pwd=".`pwd`."\n";

    # Construct Jmol command to generate still images
    my $jmol_command = "java -jar $progs->{Jmol_jar} -x ";
    $debug && print STDERR "$exe_name: \$jmol_command=$jmol_command\n";
    my $spt_stills = ($large_file) ? "$exe_dir/jmol_create_stills144.spt" : "$exe_dir/jmol_create_stills72.spt";
    my $spt_final = '';
        my $job_name = ($spt_state) ? $spt_state : $infile ;
        $job_name =~ s/[.]\w{1,7}$//; # remove the file name extension
    # Check if the input state script or PDB exists, and set up the Jmol script
    if ($spt_state) {
        if (-f "$spt_state") {
             $spt_final = 'Jmol_3Dmovie_final.spt';
             my $result = `cat $spt_state $spt_stills > $spt_final`;
             $result .= `cat $spt_final`;
             $debug && print STDERR "$exe_name: after merging the scripts, \$result=\n$result\n";
             $jmol_command .= "-s $spt_final";
             $debug && print STDERR "$exe_name: \$jmol_command=$jmol_command\n";
        } else {
            $errcode = "\$dir_path=$dir_path, \$spt_state=$spt_state, can't find such file, abort";
            print STDERR "$exe_name: \$errcode=$errcode.\n";
            &Usage();
            &finish($success, $errcode, $pwd_old, $exe_name, $dir_path, $job_name);
        }

    } elsif ($infile) {
        if (-f "$infile") {
             $jmol_command .= "$infile -s $spt_stills";
             $debug && print STDERR "$exe_name: \$jmol_command=$jmol_command\n";
        } else {
            $errcode = "\$dir_path=$dir_path, \$infile=$infile, can't find such file, abort";
            print STDERR "$exe_name: \$errcode=$errcode.\n";
            &Usage();
            &finish($success, $errcode, $pwd_old, $exe_name, $dir_path, $job_name);
        }

    } else {
            $errcode = "Need either .spt or PDB file";
            print STDERR "$exe_name: \$errcode=$errcode.\n";
            &Usage();
            &finish($success, $errcode, $pwd_old, $exe_name, $dir_path, $job_name);
    }

      # save result to $outfile
      my $OUTF;
#      $OUTF = STDOUT;
      $debug && print STDERR "$exe_name: output to STDOUT\n";

        my $msgs_all = [];

        # Launch Xvfb for this script, needed for runs on servers w/o display
        my $old_display;
        my ($Xvfb_pid, $Xvfb_display);
        my $res_Xvfb = Start_Xvfb::Xvfb();
        print STDERR "$exe_name: \$res_Xvfb=$res_Xvfb\n";
        if ($res_Xvfb =~ /PID='(\d+)'  DISPLAY='(.*?)'/i) {
            ($Xvfb_pid, $Xvfb_display) = ($1, $2);
            $old_display = `echo \$DISPLAY`;
            $ENV{'DISPLAY'} = $Xvfb_display;
#            $res_Xvfb = `export DISPLAY=$Xvfb_display`;
            $debug && print STDERR "$exe_name: new DISPLAY=".`echo \$DISPLAY`."\n";
        } else {
            $errcode = "could NOT START virtual X server 'Xvfb' or DETERMINE display_number - ABORTED $0";
            print STDERR "$exe_name: \$errcode=$errcode.\n";
            &Usage();
            &finish($success, $errcode, $pwd_old, $exe_name, $dir_path, $job_name);
        }

        # Cleaning up any existing stills movie????.gif
        my $result = &remove_files('movie????.gif');
        $debug && print STDERR "$exe_name: \$result=\n$result\n";

        # Submit the Jmol job, using Xvfb as display buffer
        print STDERR "$exe_name: \$jmol_command=$jmol_command\n";
        $result = `$jmol_command`; # Start Jmol to create the stills
        $debug && print STDERR "$exe_name: \$result=\n$result\n";
        print STDERR "$exe_name: Jmol created following still images in ".`pwd`.":\n".`ls -l movie????.gif`."\n";

        # After Jmol run, restore old display, and shut down Xvfb
        $ENV{'DISPLAY'} = $old_display;
        print STDERR "$exe_name: trying to restore to old DISPLAY=".`echo \$DISPLAY`."\n";
        $result = `kill $Xvfb_pid`;
        $debug && print STDERR "$exe_name: After kill $Xvfb_pid, \$result='$result'\n";
        !$result && $debug && print STDERR "$exe_name: Successfully terminated Xvfb: pid=$Xvfb_pid\n";

        # Use ffmpeg to create movie
        # 1. Generate the name of movie file
        my $movie_file = $job_name;
        $movie_file .= ($large_file) ? '_6400k' : '_3200k';
        $movie_file .= '.'.$format;
        # remove the file in case it already exists, to ensure any file after this step is new, or none exists
        $result = &remove_files("$dir_path/$movie_file");
        $debug && print STDERR "$exe_name: \$result=\n$result\n";

        # 2. Submit FFmpeg job
        my $ffmpeg_cmd = "";
        if ($large_file) {
#            $ffmpeg_cmd = "$progs->{ffmpeg} -r 20 -b:v 6400000 -intra -i movie%04d.gif $movie_file"; #Ver>0.10
            $ffmpeg_cmd = "$progs->{ffmpeg} -r 20 -b 6400000 -intra -i movie%04d.gif $movie_file"; #Ver=0.6
        } else {
#            $ffmpeg_cmd = "$progs->{ffmpeg} -r 10 -b:v 3200000 -intra -i movie%04d.gif $movie_file"; #Ver>0.10
            $ffmpeg_cmd = "$progs->{ffmpeg} -r 10 -b 3200000 -intra -i movie%04d.gif $movie_file"; #Ver=0.6
        }
        $debug && print STDERR "$exe_name: \$ffmpeg_cmd='$ffmpeg_cmd'\n";
        my $ffmpeg_result = `$ffmpeg_cmd`;
        $ffmpeg_result .= `ls -l $movie_file`;
        print STDERR "\n$exe_name: \$ffmpeg_result=\n$ffmpeg_result\n";

        # Check if movie is created and has non-zero size
        if (!-f "$dir_path/$movie_file") {
            $errcode = "After running ffmpeg, can't find movie file $dir_path/$movie_file";
            $debug && print STDERR "$exe_name: \$errcode=$errcode\n";
        } elsif (-z "$dir_path/$movie_file") {
            $errcode = 'After running ffmpeg, movie file $dir_path/$movie_file has zero size';
            $debug && print STDERR "$exe_name: \$errcode=$errcode\n";
        } else {
            $success = 1;
            $errcode = '';
        }

        # During production, cleaning up still movie????.gif
        if (!$debug) {
            $result = &remove_files("movie????.gif");
#            print STDERR "$exe_name: after removing the stills movie????.gif \$result=\n$result\n";
        }

    # Call sub finish to clean up
    &finish($success, $errcode, $pwd_old, $exe_name, $dir_path, $job_name, $movie_file);

    print STDERR "\n$exe_name: Finished.\n";

exit;


############# Subroutines #############

sub Usage{
    print STDERR "Usage: ./Jmol_3Dmovie.pl -large_file -d ./ -i 3CL0.pdb\n";
    print STDERR "Usage: ./Jmol_3Dmovie.pl -f avi -large_file -d ./ -i 3CL0.pdb\n";
    print STDERR "Usage: Jmol_3Dmovie.pl requires state script from Jmol or PDB file as input\n";
    print STDERR "Usage: Also requires following programs: Jmol, Xvfb, ffmpeg\n";
} # sub Usage


    my ($success, $errcode, $pwd, $exe_name, $dir_path, $job_name, $movie_file) = @_;
    my $debug = 0;

    # Create a file <>_finished.txt to indicated the finish of the script
    # This only indicates the finish of the script, to make sure the movie was generated, please check
    # for such file and its size
        if ($exe_name =~ /(.+)[.].{2,7}/) {
            $exe_name = $1;
        } else {
            $exe_name = 'null';
    }
    my $finish_fn = "${exe_name}_finished.txt";
    if (-f "$dir_path/$finish_fn") {
            print STDERR "$exe_name: Found existing file $dir_path/$finish_fn before starting, overwriting it\n";
    }
    open my $FINISHF, '>', "$finish_fn" or croak "Can't open outfile '$finish_fn': $OS_ERROR";

    print $FINISHF "$exe_name: Finished for \$job_name='$job_name'.\n";
    if ($success) {
        print $FINISHF "$exe_name: movie saved to: '$dir_path/$movie_file'.\n";
        print $FINISHF "$exe_name: Success: \$success='$success'.\n";
    } else {
        print $FINISHF "$exe_name: Failed: \$errcode='$errcode'.\n";
    }

    close $FINISHF or croak "Can't close outfile '$finish_fn': $OS_ERROR";
    print STDERR "$exe_name: Created \$finish_fn=$finish_fn\n";

    chdir($pwd) if ($pwd);
    $debug && print STDERR "$exe_name: pwd=".`pwd`."\n";

} # sub finish


sub remove_files {
    my ($ptn) = @_;
    my $debug = 0;
    my $subname = 'remove_files';

    my $result = 'Need a partern to locate files';
    !$ptn && return $result;

    # Cleaning up any existing file
    # '2>&1' is used to redirect stderr to stdout
    $result = `ls $ptn 2>& 1`;
    $debug && print STDERR "$subname: \$result=\n$result";
    if ($result !~ /No such file or directory/i) {
        $result = `rm $ptn`;
        $result .= `ls $ptn 2>& 1`;
        $debug && print STDERR "$subname: after `rm $ptn` \$result=\n$result";
    }

    return $result;
} # sub remove_files

1;
