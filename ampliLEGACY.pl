#!/usr/bin/perl -w
#
################################################################
#
# Name: ampliLEGACY.pl
#
# Version: 1.0
#
# Author: Alvaro Sebastian
#
# Support: Alvaro Sebastian (bioquimicas@yahoo.es)
#
# License: GPL
#
# Evolutionary Biology Group
# Faculty of Biology
# Adam Mickiewicz University
#
# Description:
#   Allows to perform genotyping methods previously described in the literature to amplicon sequencing (AS) data
#   Analyzes an Excel file created with AmpliSAS and gives as output an Excel file with genotyping results
#
# Requires as input one or several Excel files generated by AmpliSAS (they can be from de-multiplexed reads or clustered ones)
#
# Example:
# perl ampliLEGACY.pl -1 reads_replicate2.fq.gz -2 reads_replicate2.fq.gz -o results
#

my $VERSION = "1.2";
my $SCRIPT_NAME = fileparse($0);
my $AUTHOR = "Alvaro Sebastian";
my $DESCRIPTION = "Emulates previously published methods for genotyping amplicon sequencing data.\nThe three genotyping protocols available are described in:\nSommer et al. 2013, Radwan & Herdegen et al. 2014 and Lighten et al. 2014.";


# Modules are in folder 'lib' in the path of the script
use File::FindLib 'lib';
# Perl modules necessaries for the correct working of the script
use Cwd;
use File::Basename;
use Getopt::Long;
use Bio::Sequences;
use Bio::Ampli;

# All variables must be declared before their use
use strict;
# Turn autoflush on
local $| = 1;


my $COMMAND_LINE = $0." ".join(" ",@ARGV);

# Default options
# Default alignment algorithm
my $INP_align = 'match';

# Default recommended genotyping method parameters
my $METHOD_PARAMS = {
	'sommer' => {
		'error_threshold' => { 'all' => [ '2' ] }, # Artifacts are 1-2bp diff from putative alleles
		'cluster_inframe' => { 'all' => [ '1' ] }, # Sequences not in-frame will be artifacts
		#'cluster_exact_length' => { 'all' => [ '0' ] }, # Non exact length sequences will be consider artifacts
		'min_amplicon_depth' => { 'all' => [ '100' ] },
	},
	'lighten' => {
		'error_threshold' => { 'all' => [ '3' ] }, # Errors are 1-3bp mismatches from parental PAs
		'min_dominant_frequency_threshold' => { 'all' => [ '2' ] }, # RPEs are <2% depth respect to parental PAs
		'max_allele_number' => { 'all' => [ '10' ] }, # Maximum number of expected alleles to calculate DOCs
		'cluster_inframe' => { 'all' => [ '1' ] }, # Sequences not in-frame will be artifacts
		#'cluster_exact_length' => { 'all' => [ '0' ] }, # Non exact length sequences will be consider artifacts
		'min_amplicon_depth' => { 'all' => [ '100' ] },
	},
	'radwan' => {
		'error_threshold' => { 'all' => [ '2' ] }, # Artefacts are max. 2 substitutions from a more abundant variant
		'min_dominant_frequency_threshold' => { 'all' => [ '100' ] }, # Artefacts are <100% depth respect to parental allele (original algorithm)
		'min_amplicon_seq_frequency' => { 'all' => [ '3' ] }, # All variants <3% freq. are rejected as artifacts
		'max_amplicon_seq_frequency' => { 'all' => [ '12' ] }, # All variants >12% freq. are accepted as true alleles
		'cluster_inframe' => { 'all' => [ '1' ] }, # Sequences not in-frame will be artifacts
		#'cluster_exact_length' => { 'all' => [ '0' ] }, # Non exact length sequences will be consider artifacts
		'min_amplicon_depth' => { 'all' => [ '100' ] },
	},
};


my ($INP_reads_file,$INP_reads_file2,$INP_amplicons_file,$INP_amplicons_file2,$INP_method,$INP_outpath,$INP_nreads,$INP_nreads_amplicon,$INP_shuffle,$INP_direct,$INP_allele_file,$INP_threads,$INP_verbose,$INP_test,$INP_zip);

GetOptions(
	'h|help|?' =>  \&usage,
	'i|input=s' => \$INP_reads_file,
	'i2|input2=s' => \$INP_reads_file2,
# 	'd|data=s' => \$INP_method_params_file,
	'd|data=s' => \$INP_amplicons_file,
	'd2|data2=s' => \$INP_amplicons_file2,
	'm|method=s' => \$INP_method,
	'o|output=s' => \$INP_outpath,
	'di|direct' => \$INP_direct,
	'n|number=i' => \$INP_nreads,
	'na|max=i' => \$INP_nreads_amplicon,
	's|shuffle' => \$INP_shuffle,
	'a|alleles=s' => \$INP_allele_file,
	'thr|threads=i' => \$INP_threads,
	'v|verbose' => \$INP_verbose,
	'test' => \$INP_test,
	'z|zip' => \$INP_zip,
	'<>' => \&usage,
);

# Usage help
sub usage {
	print "\n$SCRIPT_NAME version $VERSION by $AUTHOR\n";
	print "\n$DESCRIPTION\n";
	print "\nUsage: ";
	print "$SCRIPT_NAME -i <file> -d <file> -m <method> [-i2 <file> -d2 <file>] [options]\n";
	print "\nOptions:\n";
	print "  -i <file>\tInput FASTQ or FASTA file (compressed or uncompressed).\n";
	print "  -d <file>\tCSV file with primer/amplicon data.\n";
	print "  -i2 <file>\tReplicate (only Sommer method): Input FASTQ or FASTA file (compressed or uncompressed).\n";
	print "  -d2 <file>\tReplicate (only Sommer method): CVS file with primer/amplicon data.\n";
	print "  -m <method>\tGenotyping method to apply ('Sommer', 'Lighten', 'Radwan').\n";
	print "  -o <path>\tOutput folder name.\n";
	print "  -a <file>\tFASTA file with allele names and sequences.\n";
	print "  -s\t\tShuffle/randomize reads/sequences to analyze.\n";
	print "  -v\t\tVerbose output, prints additional pseudoFASTA files with details about clustered and filtered sequences.\n";
	print "  -n <number>\tNumber of reads/sequences to analyze.\n";
	print "  -na <number>\tNumber of reads/sequences per amplicon to analyze.\n";
	print "  -di\t\tAnalyze reads only in direct sense.\n";
	print "  -thr <number>\tNumber of threads to calculate the alignments.\n";
	print "  -z\t\tCompress results in ZIP format.\n";
	print "  -h\t\tHelp.\n";
	print "\n";
	exit;

}


# Prints usage help if no input file is specified
if (!defined($INP_reads_file) && !defined($INP_reads_file2)){
	print "\nERROR: You must specify input files.\n\n";
	usage();
	exit;
} elsif (defined($INP_reads_file2) && !defined($INP_reads_file)){
	$INP_reads_file = $INP_reads_file2;
	$INP_reads_file2 = undef;
}
# Prints usage help if no input file is specified
if (!defined($INP_amplicons_file) && !defined($INP_amplicons_file2)){
	print "\nERROR: You must specify input files.\n\n";
	usage();
	exit;
} elsif (defined($INP_amplicons_file2) && !defined($INP_amplicons_file)){
	$INP_amplicons_file = $INP_amplicons_file2;
	$INP_amplicons_file2 = undef;
} elsif (defined($INP_amplicons_file) && defined($INP_reads_file2) && !defined($INP_amplicons_file2)){
	$INP_amplicons_file2 = $INP_amplicons_file;
}
# Checks technology default parameters
if (!defined($INP_method)){
	print "\nERROR: You must specify a supported genotyping method ('Sommer', 'Lighten' or 'Radwan').\n\n";
	usage();
	exit;
} else {
	$INP_method =~ s/\s//g;
	$INP_method = lc($INP_method);
	if (!defined($METHOD_PARAMS->{$INP_method})){ 
		print "\nERROR: You must specify a supported genotyping method ('Sommer', 'Lighten' or 'Radwan').\n\n";
		usage();
		exit;
	} elsif ($INP_method eq 'sommer' && (!defined($INP_reads_file2) || !defined($INP_amplicons_file2))){
		print "\nERROR: 'Sommer' method requires 2 input files (2 replicates).\n\n";
		usage();
		exit;
	} elsif (($INP_method eq 'lighten' || $INP_method eq 'radwan') && defined($INP_reads_file2)){
		print "\nERROR: '".ucfirst($INP_method)."' method accepts only 1 input file per analysis.\n\n";
		usage();
		exit;
	}
}
# Default output path
if (!defined($INP_outpath)){
	$INP_outpath  = lc((split('\.',$SCRIPT_NAME))[0]);
}

print "\nRunning '$COMMAND_LINE'\n";

# Assign dump file, only used in case of -test parameter chosen
my $dump_file = "$INP_outpath.ampli.dump";

# FOR FUTURE DEVELOPMENTS, GIVING AS INPUT EXCEL FILES
# # Reads amplicon sequences and depths
# # $amplicon_raw_sequences stores the individual unique sequence depths
# # $amplicon_raw_sequences->{$marker_name}{$sample_name}{$md5} = $depth;
# # $amplicon_raw_depths stores the total depth of the sequences into an amplicon
# # $amplicon_raw_depths->{$marker_name}{$sample_name} += $depth;
# # Reads marker/amplicon sequence data
# # $marker_seq_data stores the names and parameters of all unique sequences of a unique marker
# # $marker_seq_data->{$marker_name}{$md5} = { 'seq'=> $seq, 'name'=>$name, 'len'=>$len, 'depth'=>$unique_seq_depth, 'samples'=>$count_samples, 'mean_freq'=>$mean_freq, 'max_freq'=>$max_freq, 'min_freq'=>$min_freq };
# # $amplicon_seq_data stores the names and parameters of all unique sequences of a unique amplicon
# # $amplicon_seq_data->{$marker_name}{$sample_name}{$md5} = { 'seq'=> $seq, 'name'=>$name, 'len'=>$len, 'depth'=>$unique_seq_depth, 'freq'=>$unique_seq_frequency, 'cluster_size'=>$cluster_size };
# 
# my ($markers, $samples, $amplicon_raw_sequences, $amplicon_raw_depths, $marker_seq_data, $amplicon_seq_data);
# if (defined($INP_file)){
# 	printf("\nReading File '%s'.\n", $INP_file);
# 	($markers, $samples, $amplicon_raw_sequences, $amplicon_raw_depths) = read_amplisas_file_amplicons($INP_file);
# }
# my ($markers2, $samples2, $amplicon_raw_sequences2, $amplicon_raw_depths2, $marker_seq_data2, $amplicon_seq_data2);
# if (defined($INP_file2)){
# 	printf("\nReading File '%s'.\n", $INP_file2);
# 	($markers2, $samples2, $amplicon_raw_sequences2, $amplicon_raw_depths2) = read_amplisas_file_amplicons($INP_file2);
# }


# 2 PRIMERS => MARKER
# 1/2 TAGS => SAMPLE
# 2 PRIMERS + 1/2 TAGS => AMPLICON (Single PCR product)

# Checks if an excel file is given as input with sequences previously processed by AmpliSAS
my ($INP_excel_file,$INP_excel_file2);
if (defined($INP_reads_file) && is_xlsx($INP_reads_file)){
	$INP_excel_file = $INP_reads_file;
	if (defined($INP_reads_file2)){
		if (is_xlsx($INP_reads_file2)){
			$INP_excel_file2 = $INP_reads_file2;
		} else {
			print "\nERROR: You must specify two valid Excel files.\n\n";
		}
	}
# Prints usage help if no input file is specified
} elsif (!defined($INP_reads_file) || !defined($INP_amplicons_file)){
	print "\nERROR: You must specify input files.\n\n";
	usage();
	exit;
}

# Check and read sequences files
my ($reads_file_format,$read_seqs,$read_headers,$read_qualities,$total_reads);
my ($reads_file_format2,$read_seqs2,$read_headers2,$read_qualities2,$total_reads2);
if (!defined($INP_excel_file) && (!defined($INP_test) || !-e $dump_file)){
	($reads_file_format,$read_seqs,$read_headers,$read_qualities,$total_reads)
	= parse_sequence_file($INP_reads_file,$INP_nreads,['verbose']);
	if (defined($INP_reads_file2)){
		($reads_file_format2,$read_seqs2,$read_headers2,$read_qualities2,$total_reads2)
		= parse_sequence_file($INP_reads_file2,$INP_nreads,['verbose']);
	}
}

# Check and read amplicons files
my ($markerdata,$primers,$sampledata,$tags,$paramsdata,$alleledata);
my ($markerdata2,$primers2,$sampledata2,$tags2,$paramsdata2,$alleledata2);
if (!is_xlsx($INP_reads_file) && defined($INP_amplicons_file)){
	($markerdata,$primers,$sampledata,$tags,$paramsdata,$alleledata)
	= parse_amplicon_file($INP_amplicons_file,['verbose', 'skip samples']);
	if (defined($INP_amplicons_file2)){
		($markerdata2,$primers2,$sampledata2,$tags2,$paramsdata2,$alleledata2)
		= parse_amplicon_file($INP_amplicons_file2,['verbose', 'skip samples']);
	}
} elsif (is_xlsx($INP_reads_file) && defined($INP_amplicons_file)){
	($markerdata,$primers,$sampledata,$tags,$paramsdata,$alleledata)
	= parse_amplicon_file($INP_amplicons_file,['verbose','skip markers','skip samples']);
	if (defined($INP_amplicons_file2)){
		($markerdata2,$primers2,$sampledata2,$tags2,$paramsdata2,$alleledata2)
		= parse_amplicon_file($INP_amplicons_file2,['verbose','skip markers','skip samples']);
	}
}

# Check and read alleles file (optional)
# Amplicon data file has preference over alleles in FASTA file
if (defined($INP_allele_file) && -e $INP_allele_file){
	print "\nReading allele sequences from '$INP_allele_file'.\n";
	$alleledata = read_allele_file($INP_allele_file);
}

# Set default values for params not specified in CSV input file
my @GENOTYPING_PARAMS;
foreach my $paramname (keys %{$METHOD_PARAMS->{$INP_method}}){
	if (!defined($paramsdata->{$paramname})) {
		$paramsdata->{$paramname} = $METHOD_PARAMS->{$INP_method}{$paramname};
	}
	push(@GENOTYPING_PARAMS,$paramname);
}

# After previous checks to confirm that there are no errors in input data
# Creates output folders
my $INP_outpath_allseqs = "$INP_outpath/allseqs";
my $INP_outpath_allseqs2 = "$INP_outpath/allseqs_dup";
my $INP_outpath_legacy = "$INP_outpath/genotyping";
if (!-d $INP_outpath){
	mkdir($INP_outpath);
}
if (!defined($INP_excel_file) && !-d $INP_outpath_allseqs){
	mkdir($INP_outpath_allseqs);
}
if (!-d $INP_outpath_legacy){
	mkdir($INP_outpath_legacy);
}
if (!defined($INP_excel_file2) && defined($INP_amplicons_file2) && !-d $INP_outpath_allseqs2){
	mkdir($INP_outpath_allseqs2);
}

# Print amplicon parameters into a file
print "\nPrinting amplicon data into '$INP_outpath/amplicon_data.csv'.\n";
my $amplicon_data = print_amplicon_data($paramsdata,'params',\@GENOTYPING_PARAMS)."\n";
$amplicon_data .= print_amplicon_data($markerdata,'markers')."\n";
$amplicon_data .= print_amplicon_data($sampledata,'samples')."\n";
$amplicon_data .= print_amplicon_data($alleledata,'alleles')."\n";
write_to_file("$INP_outpath/amplicon_data.csv",$amplicon_data);
if (defined($INP_amplicons_file2)){
	my $amplicon_data2 .= print_amplicon_data($markerdata2,'markers')."\n";
	$amplicon_data2 .= print_amplicon_data($sampledata2,'samples')."\n";
	$amplicon_data2 .= print_amplicon_data($alleledata2,'alleles')."\n";
	write_to_file("$INP_outpath/amplicon_data_dup.csv",$amplicon_data2);
}

# Extracts amplicon sequences and depths
# $amplicon_raw_sequences stores the individual unique sequence depths
# $amplicon_raw_sequences->{$marker_name}{$sample_name}{$md5} = $depth;
# $amplicon_raw_depths stores the total depth of the sequences into an amplicon
# $amplicon_raw_depths->{$marker_name}{$sample_name}++;
my ($markers, $samples);
my ($md5_to_sequence,$amplicon_raw_sequences,$amplicon_raw_depths);
my ($md5_to_sequence2,$amplicon_raw_sequences2,$amplicon_raw_depths2);
my ($marker_seq_data, $amplicon_seq_data);
my ($marker_seq_data2, $amplicon_seq_data2);
my ($marker_result_file,$marker_seq_files,$marker_matrix_files);
my ($marker_result_file2,$marker_seq_files2,$marker_matrix_files2);
my ($amplicon_seq_files, $amplicon_seq_files2);
my $md5_to_name;
if (!defined($INP_excel_file)){
	if (!defined($INP_test) || !-e $dump_file){
		# Randomizes/shuffles reads
		if (defined($INP_shuffle)) {
			($read_headers,$read_seqs) = shuffle_seqs($read_headers,$read_seqs);
			if (defined($INP_reads_file2)){
				($read_headers2,$read_seqs2) = shuffle_seqs($read_headers2,$read_seqs2);
			}
		}
		print "\nDe-multiplexing amplicon sequences from reads.\n";
		# Creates a file with all sequences
		my $raw_seqs_file = write_to_file("/tmp/".random_file_name(),join("\n",@{$read_seqs}));
		my $raw_seqs_file2;
		if (defined($INP_reads_file2)){
			$raw_seqs_file2 = write_to_file("/tmp/".random_file_name(),join("\n",@{$read_seqs2}));
		}
		my $match_options;
		if (defined($INP_direct)) {
			push(@$match_options, 'direct');
		}
		# Parse reads and primers+tags with GAWK to find matching amplicons
		# Is equivalent to 'align_amplicons+match_amplicons' with perfect matching, but very fast
		if (defined($INP_threads) && $INP_threads>1){
			($md5_to_sequence,$amplicon_raw_sequences,$amplicon_raw_depths)
			= match_amplicons_regex_with_threads($raw_seqs_file,$markerdata,$sampledata,$primers,$tags,$INP_nreads_amplicon,$match_options,$INP_threads);
			if (defined($INP_reads_file2)){
				($md5_to_sequence2,$amplicon_raw_sequences2,$amplicon_raw_depths2)
				= match_amplicons_regex_with_threads($raw_seqs_file2,$markerdata2,$sampledata2,$primers2,$tags2,$INP_nreads_amplicon,$match_options,$INP_threads);
			}
		} else {
			($md5_to_sequence,$amplicon_raw_sequences,$amplicon_raw_depths)
			= match_amplicons_regex($raw_seqs_file,$markerdata,$sampledata,$primers,$tags,$INP_nreads_amplicon,$match_options);
			if (defined($INP_reads_file2)){
				($md5_to_sequence2,$amplicon_raw_sequences2,$amplicon_raw_depths2)
				= match_amplicons_regex($raw_seqs_file2,$markerdata2,$sampledata2,$primers2,$tags2,$INP_nreads_amplicon,$match_options);
			}
		}
		# Merge sequences if threre are 2 files (Sommer method)
		if (defined($md5_to_sequence2)){
			$md5_to_sequence = { %$md5_to_sequence, %$md5_to_sequence2 };
		}
		if (defined($INP_test)) {
			print "\nDumping alignment data into '$dump_file'.\n";
			store_data_dump([$md5_to_sequence,$amplicon_raw_sequences,$amplicon_raw_depths,$md5_to_sequence2,$amplicon_raw_sequences2,$amplicon_raw_depths2], $dump_file, 'Storable');
		}
		`rm $raw_seqs_file`;

		# Free memory
		undef($read_headers);
		undef($read_seqs);
		undef($read_qualities);
		if (defined($INP_reads_file2)){
			undef($read_headers2);
			undef($read_seqs2);
			undef($read_qualities2);
		}
	} else {
		print "\nRecovering de-multiplexed amplicon sequences from '$dump_file'.\n";
		($md5_to_sequence,$amplicon_raw_sequences,$amplicon_raw_depths,$md5_to_sequence2,$amplicon_raw_sequences2,$amplicon_raw_depths2) = @{recover_data_dump($dump_file, 'Storable')};
	}
	
	# Assigns samples/tags to markers
	$markers = $primers;
	foreach my $marker_name (@$markers){
		foreach my $sample_name (@$tags) {
			if (defined($amplicon_raw_depths->{$marker_name}{$sample_name})){
				push(@{$samples->{$marker_name}}, $sample_name);
			}
		}
	}
	my ($markers2,$samples2);
	if (defined($INP_amplicons_file2)){
		$markers2 = $primers2;
		foreach my $marker_name (@$markers2){
			foreach my $sample_name (@$tags2) {
				if (defined($amplicon_raw_depths2->{$marker_name}{$sample_name})){
					push(@{$samples2->{$marker_name}}, $sample_name);
				}
			}
		}
	}

	# Align sequences to alleles and assign allele names to sequences
	if (defined($alleledata) && %$alleledata){
		print "\nMatching allele sequences.\n";
		$md5_to_name = match_alleles($alleledata,$md5_to_sequence,$md5_to_name,undef,$INP_threads);
	}

	# Extracts marker/amplicon sequence data
	# $marker_seq_data stores the names and parameters of all unique sequences of a unique marker
	# $marker_seq_data->{$marker_name}{$md5} = { 'seq'=> $seq, 'name'=>$name, 'len'=>$len, 'depth'=>$unique_seq_depth, 'samples'=>$count_samples, 'mean_freq'=>$mean_freq, 'max_freq'=>$max_freq, 'min_freq'=>$min_freq,};
	# $amplicon_seq_data stores the names and parameters of all unique sequences of a unique amplicon
	# $amplicon_seq_data->{$marker_name}{$sample_name}{$md5} = { 'seq'=> $seq, 'name'=>$name, 'len'=>$len, 'depth'=>$unique_seq_depth, 'freq'=>$unique_seq_frequency, 'cluster_size'=>$cluster_size };
	if (!defined($INP_reads_file2)){
		print "\nExtracting de-multiplexed sequences into '$INP_outpath_allseqs'.\n";
	} else {
		print "\nExtracting de-multiplexed sequences into '$INP_outpath_allseqs' and '$INP_outpath_allseqs2'.\n";
	}
	($marker_seq_data, $amplicon_seq_data, $md5_to_name)
	= retrieve_amplicon_data($markers,$samples,$amplicon_raw_sequences,$amplicon_raw_depths,$md5_to_sequence,$md5_to_name);
	if (defined($INP_reads_file2)){
		($marker_seq_data2, $amplicon_seq_data2, $md5_to_name)
		= retrieve_amplicon_data($markers,$samples,$amplicon_raw_sequences2,$amplicon_raw_depths2,$md5_to_sequence,$md5_to_name);
	}
	# Prints marker sequences
	($marker_result_file,$marker_seq_files,$marker_matrix_files)
	= print_marker_sequences($markers,$samples,$marker_seq_data,$amplicon_seq_data,$amplicon_raw_depths,$INP_outpath_allseqs);
	if (defined($INP_reads_file2)){
		($marker_result_file2,$marker_seq_files2,$marker_matrix_files2)
		= print_marker_sequences($markers,$samples,$marker_seq_data2,$amplicon_seq_data2,$amplicon_raw_depths2,$INP_outpath_allseqs2);
	}
	# Prints amplicon sequences
	$amplicon_seq_files
	= print_amplicon_sequences($markers,$samples,$marker_seq_data,$amplicon_seq_data,$INP_outpath_allseqs);
	if (defined($INP_reads_file2)){
		$amplicon_seq_files2
		= print_amplicon_sequences($markers,$samples,$marker_seq_data2,$amplicon_seq_data2,$INP_outpath_allseqs2);
	}

} else {

	printf("\nReading File '%s'.\n", $INP_excel_file);
	my ($markers_, $samples_, $markers2_, $samples2_);
	($markers_, $samples_, $amplicon_raw_sequences, $amplicon_raw_depths, $md5_to_sequence) = read_amplisas_file_amplicons($INP_excel_file,[],$INP_nreads_amplicon);
	if (defined($INP_excel_file2)){
		printf("\nReading File '%s'.\n", $INP_excel_file2);
		($markers2_, $samples2_, $amplicon_raw_sequences2, $amplicon_raw_depths2, $md5_to_sequence2) = read_amplisas_file_amplicons($INP_excel_file,[],$INP_nreads_amplicon);
		# Merge sequences if threre are 2 files (Sommer method)
		if (defined($md5_to_sequence2)){
			$md5_to_sequence = { %$md5_to_sequence, %$md5_to_sequence2 };
		}
	}

	# Uses the markers specified in the Excel file
	$markers = $markers_;

	# Assigns samples/tags to markers
	foreach my $marker_name (@$markers_){
		foreach my $sample_name (@{$samples_->{$marker_name}}) {
			if (defined($amplicon_raw_depths->{$marker_name}{$sample_name})){
				push(@{$samples->{$marker_name}}, $sample_name);
			} elsif (is_numeric($sample_name) && defined($amplicon_raw_depths->{$marker_name}{sprintf('%d',$sample_name)})){
				# For example sample '001' could be writen into Excel as '1'
				push(@{$samples->{$marker_name}}, sprintf('%d',$sample_name));
			}
		}
	}

	# Recalculates marker and amplicon data
	($marker_seq_data, $amplicon_seq_data, $md5_to_name)
	= retrieve_amplicon_data($markers,$samples,$amplicon_raw_sequences,$amplicon_raw_depths,$md5_to_sequence,$md5_to_name);
	if (defined($INP_excel_file2)){
		($marker_seq_data2, $amplicon_seq_data2, $md5_to_name)
		= retrieve_amplicon_data($markers,$samples,$amplicon_raw_sequences,$amplicon_raw_depths,$md5_to_sequence,$md5_to_name);
	}

	# Align sequences to alleles and assign allele names to sequences
	if (defined($alleledata) && %$alleledata){
		print "\nMatching allele sequences.\n";
		$md5_to_name = match_alleles($alleledata,$md5_to_sequence,$md5_to_name,undef,$INP_threads);
	}
}


print "\nChecking data and setting marker lengths.\n";
# Checks if marker lengths are defined, if not they will be calculated automatically if they are required
foreach my $marker_name (@$markers){
	my $length_type = 'manual';
	# Calculates automatically marker length in case of not being specified
	#if (defined($paramsdata->{'cluster_exact_length'}{'all'}) || defined($paramsdata->{'cluster_inframe'}{'all'}) || defined($paramsdata->{'cluster_exact_length'}{$marker_name}) || defined($paramsdata->{'cluster_inframe'}{$marker_name})){
	if (!defined($markerdata->{$marker_name}{'length'})){
		$markerdata->{$marker_name}{'length'} = adjust_automatic_params([$marker_name],$samples,$marker_seq_data,$amplicon_seq_data,['only lengths'])->{$marker_name};
		$length_type = 'auto';
	}
	if ($#{$markerdata->{$marker_name}{'length'}} == 0){
		printf("\tMarker '%s' length: %s (%s)\n",$marker_name,$markerdata->{$marker_name}{'length'}[0],$length_type);
	} else {
		printf("\tMarker '%s' lengths: %s (%s)\n",$marker_name,join(',',@{$markerdata->{$marker_name}{'length'}}),$length_type);
	}
}

# Filter markers and samples with low coverage or not desired
foreach my $marker_name (keys %{$amplicon_seq_data}){
	# Skips markers without data
	if (!defined($amplicon_seq_data->{$marker_name})){
		delete($amplicon_seq_data->{$marker_name});
		next;
	}
	# Exclude amplicons not in the list
	if (defined($paramsdata->{'allowed_markers'}) && !defined($paramsdata->{'allowed_markers'}{'all'}) && !in_array($paramsdata->{'allowed_markers'},$marker_name)){
		delete($amplicon_seq_data->{$marker_name});
		next;
	}
	foreach my $sample_name (keys %{$amplicon_seq_data->{$marker_name}}){
		# Exclude samples not in the list
		if (defined($paramsdata->{'allowed_samples'}) && !defined($paramsdata->{'allowed_samples'}{'all'}) && !defined($paramsdata->{'allowed_samples'}{$marker_name})){
			delete($amplicon_seq_data->{$marker_name}{$sample_name});
			next;
		}
		if (defined($paramsdata->{'allowed_samples'}) && !defined($paramsdata->{'allowed_samples'}{'all'}) && ref($paramsdata->{'allowed_samples'}{$marker_name}) eq 'ARRAY' && !in_array($paramsdata->{'allowed_samples'}{$marker_name},$sample_name) ){
			delete($amplicon_seq_data->{$marker_name}{$sample_name});
			next;
		}
		# Exclude samples with low coverage
		my $total_seqs = $amplicon_raw_depths->{$marker_name}{$sample_name};
		if (defined($paramsdata->{'min_amplicon_depth'}) && defined($paramsdata->{'min_amplicon_depth'}{'all'}) && (!defined($total_seqs) || $total_seqs<$paramsdata->{'min_amplicon_depth'}{'all'}[0])){
			delete($amplicon_seq_data->{$marker_name}{$sample_name});
			next;
		} elsif (defined($paramsdata->{'min_amplicon_depth'}) && defined($paramsdata->{'min_amplicon_depth'}{$marker_name}) && (!defined($total_seqs) || $total_seqs<$paramsdata->{'min_amplicon_depth'}{$marker_name}[0])){
			delete($amplicon_seq_data->{$marker_name}{$sample_name});
			next;
		}
	}
}

# Apply genotyping method
my ($amplicon_genotyped_sequences, $amplicon_genotyped_depths, $genotyping_output);
printf("\nGenotyping sequences with '%s' method and the following criteria ('parameter' 'marker' 'values'):\n",ucfirst($INP_method));
# In $paramsdata hash there are also clustering thresholds
foreach my $genotyping_param (@GENOTYPING_PARAMS){
	if ($genotyping_param ne 'allowed_markers' && defined($paramsdata->{$genotyping_param})) {
		foreach my $marker_name (sort keys %{$paramsdata->{$genotyping_param}}){
			print "\t$genotyping_param\t$marker_name\t".join(',',@{$paramsdata->{$genotyping_param}{$marker_name}})."\n";
		}
	} elsif (defined($paramsdata->{$genotyping_param})) {
		print "\t$genotyping_param\t".join(',',@{$paramsdata->{$genotyping_param}})."\n";
	}
}
print "\n";
if ($INP_method eq 'sommer'){
	($amplicon_genotyped_sequences,$amplicon_genotyped_depths,$genotyping_output)
	= genotype_amplicon_sequences($INP_method,$markers,$samples,$markerdata,$paramsdata,[$marker_seq_data,$marker_seq_data2],[$amplicon_seq_data,$amplicon_seq_data2]);
} elsif (defined($INP_threads) && $INP_threads>1){
	($amplicon_genotyped_sequences,$amplicon_genotyped_depths,$genotyping_output)
	= genotype_amplicon_sequences_with_threads($INP_method,$markers,$samples,$markerdata,$paramsdata,$marker_seq_data,$amplicon_seq_data,$INP_threads);
} else {
	($amplicon_genotyped_sequences,$amplicon_genotyped_depths,$genotyping_output)
	= genotype_amplicon_sequences($INP_method,$markers,$samples,$markerdata,$paramsdata,$marker_seq_data,$amplicon_seq_data);
}

# Writes FASTA files with real allele sequences and artifacts clustered together
if (defined($INP_verbose)){
	print "\nPrinting verbose information about alleles and artifacts into '$INP_outpath_legacy'.\n";
	foreach my $marker_name (@$markers){
		if (!defined($genotyping_output->{$marker_name})){
			next;
		}
		foreach my $sample_name (@{$samples->{$marker_name}}){
			if (!defined($genotyping_output->{$marker_name}{$sample_name})){
				next;
			}
			write_to_file("$INP_outpath_legacy/$marker_name-$sample_name.verbose.fasta",$genotyping_output->{$marker_name}{$sample_name});
		}
	}
}

print "\nExtracting putative allele sequences into '$INP_outpath_legacy'.\n\n";
# Frequencies will be calculated with original depths, not after clustering+genotyping ones
($marker_seq_data, $amplicon_seq_data, $md5_to_name)
= retrieve_amplicon_data($markers,$samples,$amplicon_genotyped_sequences,$amplicon_raw_depths,$md5_to_sequence,$md5_to_name);
($marker_result_file,$marker_seq_files,$marker_matrix_files)
= print_marker_sequences($markers,$samples,$marker_seq_data,$amplicon_seq_data,$amplicon_raw_depths,$INP_outpath_legacy,$amplicon_raw_sequences);
# Copy Excel results file to output parent folder
`cp $marker_result_file $INP_outpath/results.xlsx`;
$amplicon_seq_files
= print_amplicon_sequences($markers,$samples,$marker_seq_data,$amplicon_seq_data,$INP_outpath_legacy);

# Print number of unique sequences per amplicon
my $summary_output = "Amplicon\tTotal\tUnique";
$summary_output .= "\tTotal-$INP_method\tAlleles-$INP_method";
$summary_output .= "\n";
foreach my $marker_name (@$markers){
	foreach my $sample_name (@{$samples->{$marker_name}}) {
		$summary_output .= sprintf("%s-%s",$marker_name,$sample_name);
		if (defined($amplicon_raw_depths->{$marker_name}{$sample_name})){
			$summary_output .= sprintf("\t%d\t%d",$amplicon_raw_depths->{$marker_name}{$sample_name},scalar keys %{$amplicon_raw_sequences->{$marker_name}{$sample_name}});
		} else {
			$summary_output .= sprintf("\t%d\t%d",0,0);
		}
		if (defined($amplicon_genotyped_depths->{$marker_name}{$sample_name})){
			$summary_output .= sprintf("\t%d\t%d",$amplicon_genotyped_depths->{$marker_name}{$sample_name},scalar keys %{$amplicon_genotyped_sequences->{$marker_name}{$sample_name}});
		} else {
			$summary_output .= sprintf("\t%d\t%d",0,0);
		}
		$summary_output .= "\n";
	}
}
print "\nSequences per amplicon:\n$summary_output\n";
write_to_file("$INP_outpath/summary.txt",$summary_output);

if (defined($INP_zip) && -d $INP_outpath && !is_folder_empty($INP_outpath)){
	my $cwd = getcwd;
	chdir($INP_outpath);
	my $outname = basename($INP_outpath);
	`zip -qrm $outname.zip *` ;
	`mv $outname.zip ..`;
	chdir($cwd);
	rmdir($INP_outpath);
	print "\nAnalysis results stored into '$INP_outpath.zip'.\n\n";
} elsif (-d $INP_outpath && !is_folder_empty($INP_outpath)){
	print "\nAnalysis results stored into '$INP_outpath'.\n\n";
} else {
	print "\nThere was some error in the analysis and no results were retrieved.\n\n";
}






















