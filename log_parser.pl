# This script grabs all output logs from a tester in the current directory and converts the
# desired data to a csv file for easier use in graphing IV curves and similar 1st Si tasks. 
# If Vcc data is being parsed, the related JMP script will be executed.
#
# The methodology for parsing the given log is contained in the 
# log_parse_config.xml file, to be kept in the same directory.
# 
# CURRENTLY REV ONLY FOR VCC
# Rev 3.1 3/12/2014 S. Stern    -Modified to capture ALL logs in current directory, parse regex makes it so only useful data is captured.
#                               -Instance counting is now more intelligent and increments properly for multiple tests in single logs and across multiple die logs.

use strict;
use warnings;
use Cwd;
use Text::CSV_XS;
use XML::Simple qw(:strict);
# use feature qw(switch);
use File::Copy;

my $config = XMLin('log_parse_config.xml', ForceArray => 0, KeyAttr => [qw(opt)]);
my $filename;
my $choice;

# print "Enter log filename: ";
# chomp($filename = <>);

# Print list of modules from config file to choose from and grab user choice
foreach(keys $config->{Module}) {
    print "$_ - $config->{Module}->{$_}->{name}\n";
}
print "Enter number corresponding to desired log content: ";
chomp($choice = <>);

# Grab ALL log files in directory. We'll rely on good regex to grab the right data out of any Log.
my @logList = glob("*.Log");

# General globals
my $unique_label;
my %instance_counter = ();
my @output_line;
my $line;

# Determine output file name, column headers, etc
my $output_file = $config->{Module}->{$choice}->{name};
my @headers = @{$config->{Module}->{$choice}->{column_headers}->{header}};
my $lines_to_skip = $config->{Module}->{$choice}->{lines_to_skip};

# Get regex
my $begin_block_regex = qr/$config->{Module}->{$choice}->{begin_block_regex}/is;
my $data_regex = qr/$config->{Module}->{$choice}->{data_regex}/is;
my $parse_regex = qr/$config->{Module}->{$choice}->{parse_regex}/is;
my $unique_label_regex = qr/$config->{Module}->{$choice}->{unique_label_regex}/is;

# Generate a unique file name based on date and time to avoid overwriting any previous data collection. Thanks for the idea, Kane! <3
my @now = localtime();
my $timeStamp = sprintf("%04d_%02d_%02d_%02d%02d%02d", 
                        $now[5]+1900, $now[4]+1, $now[3],
                        $now[2],      $now[1],   $now[0]);

open my $OUTPUT,">","$timeStamp\_$output_file.csv" or die "Cannot create $output_file.csv: $!";

# Setup the CSV print object and inject the headers for this file
my $csv = Text::CSV_XS->new ({ binary => 1, eol => $/ });
$csv->print($OUTPUT, \@headers);

foreach(@logList) {
    open (FILE, $_) or die "Cannot open $_: $!";

    # Populate the rest of the CSV
    while (<FILE>) {
        chomp;
        # Check for first line of file indicating a block of data
        if ($_ =~ $begin_block_regex) {
            # Look for a unique identifier, such as the supply name in VCC when all data is formatted the same but for different supplies
            if (defined $unique_label_regex) {
                if ($_ =~ $unique_label_regex) {
                    $unique_label = $1;

                    # Account for multiple vcc outputs with same pin name due to surge testing or testing across multiple die
                    if (defined $instance_counter{$unique_label}) {
                        $instance_counter{$unique_label}++;
                    } else {
                        $instance_counter{$unique_label} = 0;
                    }
                } 
            }

            # Skip a defined number of lines to get from current line to the actual data table
            for (my $i = 0; $i < $lines_to_skip; $i++) {
                $line = readline(FILE);
            }

            # Check line for indicator that there is data, compare to regex, and store to array reference for print to csv
            while ($line =~ $data_regex) {
                @output_line = ();
                # Use the unique identifier if we're on a module like VCC that needs it
                push(@output_line, $instance_counter{$unique_label}) if $choice == 1;
                push(@output_line, $unique_label) if defined $unique_label;
                # Append data after labels, if any
                push(@output_line, $line =~ $parse_regex);
                # Write to CSV
                $csv->print($OUTPUT, \@output_line);
                
                $line = readline(FILE);
            }
        }
    }

    close FILE;
}

print "Parse and conversion to $timeStamp\_$output_file.csv complete\n";
close $OUTPUT;

# Run the JMP script to plot IV curves for all or particular power supplies if we're parsing Vcc Cont data
if ($choice == 1) {
    # Make a copy of the csv file we just generated, with the non-unique filename the JMP script expects
    copy("$timeStamp\_$output_file.csv","$output_file.csv");
    my $dir = getcwd();

    print "Executing JMP script for Vcc Characterization\n";
    system("C:\\Program Files\\SAS\\JMP\\9\\Jmp.exe", "$dir\\Vcc_Characterization.jsl");
}

# Code for VIPR, EDM, etc scripting goes here as desired