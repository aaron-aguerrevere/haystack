#!/usr/bin/perl
# ------------------------------------------------------------------------------
# Script: 		SaltLakeOnlineOnlyParser.pl
# Description:	Perl script to parse out online only death notices sent to 
#               Legacy.com from the Salt Lake Tribune. Notices post to both 
#               the SaltlakeTribune and DeseretNews sites
# Author:		Legacy.com
# Last Edit: 	09/11/2001
#
# Last Edit  Who  Description
# ---------  ---  ------------------------------------------------------------
# 06/29/18   RVD  Initial release. Cloned from SaltLakeParser.pl. Post the 
#                 online only obits to the Salt Lake and Deseret News sites. (CS-25452)
# 10/03/19   PTB  Updates splitname to preserve name order (CS-30684)
# ------------------------------------------------------------------------------
#
######################################## PACKAGES #######################################

use warnings;
use strict;

require ("../Common/ODBCSubs.pl"     );
require ("../Common/Common.pl"       );
require ("../Common/CommonTools.pl"  );
require ("../Common/LocalSettings.pl");

use Win32::ODBC;
use File::Copy;
use Image::Size;
use v5.10;


######################################## CONSTANTS #######################################

use constant TRUE                        => 1;
use constant FALSE                       => 0;
use constant PAYMENT_CODE_OBIT_PAID      => "Legacy Notice";
use constant PAYMENT_CODE_OBIT_FREE      => "Legacy Notice (Free)";
use constant PAYMENT_CODE_MEMORIAM       => "Legacy Notice (In memoriam)";
use constant PAYMENT_CODE_FEATURED       => "Featured Guestbook";
use constant FILE_SUCCESS                => 0;
use constant FILE_ERROR_OPEN_FAILED      => 1;
use constant FILE_ERROR_FILENAME_FORMAT  => 2;
use constant FILE_ERROR_NOTICE_FAILED    => 10;
use constant NOTICE_SUCCESS              => 0;
use constant NOTICE_ERROR                => 1;
use constant CONVERT_PHOTO_OPTIONS       => ' -type TrueColor +antialias -quality 100 -density 300 -scale "500x500>" ';
use constant CONVERT_LOGO_OPTIONS        => ' -type TrueColor +antialias -quality 100 -density 300 -scale "170x100>" ';
use constant CONVERT_ICON_OPTIONS       => ' -type TrueColor +antialias -quality 100 -density 300 -scale "100x100>" ';
use constant GB_SPONSOR_LENGTH_ONEYEAR   => '365';
use constant GB_SPONSOR_LENGTH_PERMANENT => '36500';
use constant NOTICE_LENGTH_PERMANENT     => '36500';
use constant SHOW_NOTICE_LINE_BREAKS     => TRUE;
use constant PRESERVE_NAME_ORDER         => 1;
use constant CHANGE_NAME_ORDER           => 0;
use constant FIX_CASE_YES                => 1;
use constant FIX_CASE_NO                 => 0;
use constant FINISHFILE_STOREIN_NEWDIR_YES => 1;
use constant FINISHFILE_STOREIN_NEWDIR_NO => 0;
use constant FINISHFILE_TIMESTAMP_YES    => 1;
use constant FINISHFILE_TIMESTAMP_NO     => 0;
use constant SHOW_IN_SPOTLIGHT_YES       => 1;
use constant SHOW_IN_SPOTLIGHT_NO        => 0;
use constant MISSING_IMAGE_FEED_PREFIX   => 'mi_';
use constant CREATE_IMAGE_ERROR_FEED     => FALSE;
use constant ENABLE_MAIN_PHOTO           => TRUE;
use constant REAL_TIME_POST              => FALSE;
use constant MOVE_FEEDFILE_AFTER_RUN     => TRUE; # FALSE for parser development only
use constant AUTO_GEN_MEMORIAM_UPSELL    => FALSE;
use constant SEND_UNMAPPED_ICON_ALERT    => FALSE;
use constant ALLOW_DECEASED_NAME_UPDATE  => FALSE;

# only bring these modules in if necessary
if (AUTO_GEN_MEMORIAM_UPSELL) 
{
	use HTTP::Request::Common qw(POST);
	use LWP::UserAgent; # memoriam upsell
}

###################################### GLOBAL VARIABLES #################################

#----------------------------------------------------------------------------------------
# $strCobrand is actually used to refer to the FTP Folder where the data feed is located.
#----------------------------------------------------------------------------------------
our $strCobrand      = "SaltLakeTribune";
die "Please set $strCobrand\n" if ( $strCobrand eq "COBRAND\_NAME_" );
our $strCurDir       = "";
our $strConnStr      = "";
our $strImageRoot    = "";
our $strNoticeDir    = "";
our $strSummaryDir   = "";
our $strErrorDir     = "";
our $strSuccessDir   = "";
our $strPhotoSaveDir = "";
our $strFirstName    = "";
our $strMiddleName   = "";
our $strLastName     = "";
our $strNickName     = "";
our $strMaidenName   = "";
our $strNamePrefix   = "";
our $strNameSuffix   = "";
our $strWinZipDir    = "";
our $strConfigFile   = "";
our $memoriamUpsellInsertUrl = "";
our $memoriamUpsellDeleteUrl = "";

SetLocalSettings();

#---------------------------------------------------------------------------------------------------------------------------------------
# $strNewspaper is the used as the actual co-brand name inserted into the database and in most cases the same as the $strCobrand value.
#---------------------------------------------------------------------------------------------------------------------------------------
my $strNewspaper      = $strCobrand;
my $strNewspaperGroup = "";

$strConfigFile = "$strCurDir/$strNewspaper" . "_IconConfig.txt";

# for memoriam upsell
my $ua = "";
#   $ua = LWP::UserAgent->new;
#   $ua->timeout(30);

# -----------------------------
# Set directory structure
# -----------------------------
$strNoticeDir .= 'Deaths';

my $strNoticePhotoDir = "$strNoticeDir/Photos";
my $strProdPhotoDir   = "$strImageRoot/Cobrands/$strNewspaper/Photos";
my $strProdLogoDir    = "$strImageRoot/Cobrands/$strNewspaper/Logos";
my $strProdIconDir    = "$strImageRoot/obiticons";
my $strPhotoWebRoot   = "/Images/Cobrands/$strNewspaper/Photos";
my $strLogoWebRoot    = "/Images/Cobrands/$strNewspaper/Logos";
my $strIconWebRoot    = "/Images/obiticons";

mkdir $strNoticeDir      if ( not -d $strNoticeDir );
mkdir $strNoticePhotoDir if ( not -d $strNoticePhotoDir );
mkdir $strProdPhotoDir   if ( not -d $strProdPhotoDir );
mkdir $strProdLogoDir if ( not -d $strProdLogoDir );

# ---------------------
# Initialize variables.
# ---------------------
my @photos               = ();
my @logos                = ();
my @icons                = ();
my $intPhotoCount        = 0;
my $strImage             = "";
my $strImageType         = "";
my $strDateStamp         = GetCurrentDate();
my $strCurrentDate       = "$2/$3/$1" if ( $strDateStamp =~ /(\d\d\d\d)(\d\d)(\d\d)/ ); # use 4 real time posting
my $strTimeStamp         = GetCurrentTime();
my $fileStatus           = FILE_SUCCESS;
my $strCompleteFeed      = "";
my $strCompleteNotice    = "";
my $strCity              = "";
my $strState             = "";
my $strCounty            = "";
my $strLocationInfo      = "";
my $strDeathNotice       = "";
my $strDeathNoticeClean  = "";
my $strAdId              = "";
my $strDeathNoticeName   = "";
my $strStopDate          = "";
my $strDeathNoticeDate   = "";
my $strPaymentCode       = "";
my $strNoticeType        = "";
my $strYearDeceased      = "";
my $strYearBorn          = "";
my $strNoticeYears       = "";
my $intShowInSpotlight   = 0;
my $hasMemoriamUpsell    = FALSE;
my $deleteMemoriamUpsell = FALSE;
my $strDateOfDeath       = "";
my $strMemUpsellText     = "";
my $strMemUpsellMainPhoto       = "";
my $intMemUpsellMainPhotoWidth  = "0";
my $intMemUpsellMainPhotoHeight = "0";
my $dateStartPrint       = "";
my $dateEndPrint         = "";
my $strEmail             = "";
my $strFuneralHome       = "";
my $strFuneralHomeId     = "";
my $strFuneralHomeAddr   = "";
my $strFuneralHomeCity   = "";
my $strFuneralHomeState  = "";
my $strFuneralHomeZip    = "";
my $strFuneralHomePhone  = "";
my $strFuneralHomeInfo   = "";
my $strPublishedBy       = "";
my $intSkipAd            = FALSE;
my $strLogFile           = "";
my $strFileDate          = "";
my $strMainPhoto         = "";
my $intMainPhotoHeight   = 0;
my $intMainPhotoWidth    = 0;
my $strSponsorName       = "";
my $strSponsorEmail      = "";
my $intSponsorshipLength = "";
my $intNoticeExpirationDays = "";
my @gbSponsorShipArrayOfHashes = ();
my %errorTypes           = ();
my $thisFileDataErrors   = "";
my $allBadImageNotices   = "";
my $missingImage         = FALSE;
my %names                = ();
my $max_name_length      = 0;
my $strIconCodes         = "";
my %iconMap              = ();
my %affiliateIcons       = ();
my %unmapped_icons       = ();
my $intAllowNameUpdate   = FALSE;
my $strDeathNoticeCopy   = "";

my @OnlineOnlyCobrands = qw( SaltLakeTribune DeseretNews );


#--------------------------
# Report: Variables
#--------------------------
my %intAdIdCntr           = ();
my %intNoticeTypeCntr     = ();
my %missing_images        = ();
my %found_images          = ();
my %dateRangeCount        = ();
my %badNames              = ();
my %intAdInFeedCntrHash   = ();
my %MainPhotoHash         = ();
my %MemUpsellMainPhotoHash = ();
my %intValidatedEmailCntr = ();
my %strWeirdChars         = ();
my %dateRangeLinks        = ();
my $intAdInFeedCntr       = 0;
my $strRepHashKey         = "";
my $intEmailCntr          = 0;
my %dateStamps            = ();
my $intUnmappedIcon      = FALSE;
my $strReportDate        = "";
my $line                 = "";
my $error                = "";
my $intNoErrors          = TRUE;
my $strDataError         = "";

my @notices = ();

# -----------------------
# Process custom switches
# -----------------------
my  $intPosting   = TRUE;
our $intDebugMode = FALSE;
for (@ARGV)
{
	if ( /^-skippost/ ) { $intPosting   = FALSE }
	if ( /^-dbg/i )     { $intDebugMode = TRUE }
}

# -----------------
# Open summary file and set output autoflush for open filehandles
# -----------------
our $strSummaryLogFile = $strSummaryDir . "OBT_". $strCobrand . "_" . $strDateStamp . "_Summary.log";
open   SUMMARY, ">>" . $strSummaryLogFile or die "\nCould not open summary log text file:  $!";
select SUMMARY; $| = TRUE;
select STDERR;  $| = TRUE;
select STDOUT;  $| = TRUE;

# -------------------------
# Print beginning messages.
# -------------------------
DebugPrint(   "$0 invoked with Process ID: $$ on (" . (localtime) . ")\n\n");
print SUMMARY "$0 invoked with Process ID: $$ on (" . (localtime) . ")\n\n";

# -----------------
# Open and initialize report file
# -----------------
my $reportDir = $strNoticeDir . "\/Reports\/";
mkdir $reportDir if (! -d $reportDir);
my $reportFile = $reportDir . $strNewspaper . "_OBT_" . GetCurrentDate() . "__" . GetCurrentTime() . ".csv";

DebugPrint("report file is $reportFile\n");

open   REPORT, ">" . $reportFile or die "\nCould not open report file: $!\n";
my $header = "\"Feed file name\"," . "\"Date Stamp\"," . "\"Ad Id\"," . "\"Post Date\"," . "\"Notice Type\"," . "\"Deceased Name\"," . "\"Processing Errors\"" . "\n";
print REPORT $header;

# ------------------------------------------------
# Open connection to the database if we're posting
# ------------------------------------------------
my $data;
if ($intPosting && (not ($data = OpenDB($strConnStr)))) {
	print SUMMARY "unable to open a DB connection with '$strConnStr'\n";
	die           "unable to open a DB connection with '$strConnStr'\n";
}

if(-s $strConfigFile)
{
	&obtLoadIconMap;
}

# ------------------------------------------
# Set the indicator to allow the parser to
# update the deceased name.
# ------------------------------------------
$intAllowNameUpdate = ALLOW_DECEASED_NAME_UPDATE;
DebugPrint("\nintAllowNameUpdate = $intAllowNameUpdate\n");

# -----------------------------------------------------------------
# Open notice directory for reading, go there and get list of files
# -----------------------------------------------------------------
unless ( opendir NOTICEDIR, $strNoticeDir )
{
	print SUMMARY "Could not read notice directory:  $!\n\nParsing process complete ... goodbye!\n\n";
	die         "\nCould not read notice directory:  $!";
}
chdir($strNoticeDir);
my @feedFiles = readdir(NOTICEDIR);
close NOTICEDIR;

DebugPrint("\nNoticeDir     (" . $strNoticeDir      . ")\n");
DebugPrint("NoticePhotoDir  (" . $strNoticePhotoDir . ")\n");
DebugPrint("PhotoArchiveDir (" . $strPhotoSaveDir   . ")\n");
DebugPrint("ProdPhotoDir    (" . $strProdPhotoDir   . ")\n");
DebugPrint("ProdLogoDir     (" . $strProdLogoDir    . ")\n");
DebugPrint("ProdIconDir     (" . $strProdIconDir    . ")\n");
DebugPrint("strPhotoWebRoot (" . $strPhotoWebRoot   . ")\n");
DebugPrint("strLogoWebRoot  (" . $strLogoWebRoot    . ")\n");
DebugPrint("strIconWebRoot  (" . $strIconWebRoot    . ")\n");
DebugPrint("strConnStr      (" . $strConnStr        . ")\n");
DebugPrint("DateStamp       (" . $strDateStamp      . ")\n\n");

# -------------------------------------------------------------
# Loop through the death notice files
# -------------------------------------------------------------
foreach ( @feedFiles )
{
	$strLogFile = $_;
	next if (-d $strLogFile);

	my ($year, $month, $day);
	# ---------------------------------------------------------
	# Only process death notice files.
	# SPECS: whatever_YYYYMMDD.xml
	# ---------------------------------------------------------
	my $fileNamePattern = '(?:obituaries|memoriam)_(\d{8})_OL_.*?\.xml$';
	if ( $strLogFile !~ /$fileNamePattern/is )
	{
		DebugPrint(   "($strTimeStamp) Wrong filename format, skipping file $strLogFile\n" );
		FinishFile(FILE_ERROR_FILENAME_FORMAT, $strLogFile, FINISHFILE_STOREIN_NEWDIR_NO, $strLogFile, FINISHFILE_TIMESTAMP_YES) if ($intPosting);
		next; # next file
	}
	($year, $month, $day) = ($1, $2, $3);
	$strFileDate = $month ."/". $day ."/". $year;

	DebugPrint("($strTimeStamp) Processing file $strLogFile\n");

	# -------------------------
	# Set up input file handle.
	# -------------------------
	unless ( open FEEDFILE, $strLogFile )
	{
		FinishFile(FILE_ERROR_OPEN_FAILED, $strLogFile, FINISHFILE_STOREIN_NEWDIR_NO, $strLogFile, FINISHFILE_TIMESTAMP_YES) if ( $intPosting );
		next; # next file
	}

	#binmode FEEDFILE; # uncomment this to successfully remove hex 00
	$strCompleteFeed = join "", <FEEDFILE>;
	close FEEDFILE;
	

	#DebugPrint("Feed is utf8, converting to windows-1252 which sql server expects from win32::odbc\n");
	# this section works when we know the input is utf8, all funny characters get mapped automagically
	# you can test this by running the  Report: Weird characters code before and after this section
	use Encode;
	$strCompleteFeed = decode_utf8( $strCompleteFeed );
	# convert the utf-8 string to "ANSI" so that it gets into the DB correctly
	$strCompleteFeed = Encode::encode("Windows-1252", $strCompleteFeed);

	$strCompleteFeed = &cmnCleanUpDataFeed( $strCompleteFeed );

	#-------------------------
	# Report: Weird characters
	#-------------------------
	my %strTempWeirdChars = &getWordsWithWeirdChars($strCompleteFeed);
	foreach  (keys %strTempWeirdChars) {
		$strRepHashKey = sprintf('%-60s',$strLogFile) . sprintf('%-20s',$_);
		$strWeirdChars{$strRepHashKey} = $strTempWeirdChars{$_};
	}

	#---------------------------------
	# Report: Init ad counter by feed.
	#---------------------------------
	$intAdInFeedCntr    = 0;
	$fileStatus         = FILE_SUCCESS;
	$allBadImageNotices = "";

	# --------------------------------------
	# Loop through the ads
	# --------------------------------------
	while ( $strCompleteFeed =~ m!^.*?(<obit>.*?</obit>)(.*)$!is )
	{
		$strCompleteFeed   = $2;
		$strCompleteNotice = $1;
		my $fullNotice = $strCompleteNotice;

		#------------------------------------------
		# Initialize all Ad variables for this ad
		#------------------------------------------
		obtInitAdVars();

		#-------------------------------------------------
		# Extract the values for the above variables here.
		#-------------------------------------------------
		obtExtractFieldsFromFeed();

		if ($intSkipAd) {
			DebugPrint("Skipping this record...\n");
			next;
		}

		foreach $strNewspaper (@OnlineOnlyCobrands) 
		{
			DebugPrint("strNewspaper is $strNewspaper\n");

#			$strPhotoWebRoot   = "/Images/Cobrands/$strNewspaper/Photos";
#			$strLogoWebRoot    = "/Images/Cobrands/$strNewspaper/Logos";
#			DebugPrint("strPhotoWebRoot is $strPhotoWebRoot\n");
#			DebugPrint("strLogoWebRoot is $strLogoWebRoot\n");
			
			#-------------------------------
			# Process photos and logos here!
			#-------------------------------
			obtProcessFTPPhotoAndLogo( \@photos, \@logos, $strNewspaper );
			if ($missingImage) {
				$allBadImageNotices .= "$fullNotice\n";
			}

			#---------------------
			# Process icons here!
			#---------------------
			obtProcessFTPIcon( \@icons);
			if ($missingImage) {
				$allBadImageNotices .= "$fullNotice\n";
			}

			#--------------------------------
			# Cleanup death notice characters.
			#--------------------------------
			obtCleanupDeathNoticeCharacters();
			DebugPrint("Death Notice = (" . $strDeathNotice .") [" . (length  $strDeathNotice) . "]\n");

			#---------------------------------------------------
			# run SQL if we're posting and have no notice errors
			#---------------------------------------------------

			obtRunSQLIfAppropriate($strNewspaper);

		}

		# ----------------------------------------------------
		# If a processing error occurred write the error
		# info out to the error report file.
		# ----------------------------------------------------
		if($error)
		{
			$error =~ s/.*\](.*)\"/$1/is;
			$line .= $error . "\n";
			print REPORT $line;
			$intNoErrors = FALSE;
			DebugPrint("line = " . $line . "\n");
		}
	}# end Ad Loop

	#------------------------------------------------
	# Report: Breakdown by feed file and upload time
	#------------------------------------------------
	my $thisLogFileFullPath = $strNoticeDir . "/" . $strLogFile;
	my @thisFileInfo        = stat $thisLogFileFullPath;
	my $thisModifiedTime    = $thisFileInfo[9];
	if ($thisModifiedTime) {
		@thisFileInfo     = localtime($thisModifiedTime);
		$thisModifiedTime = sprintf( "%02d/%02d/%04d",($thisFileInfo[4]+1),$thisFileInfo[3],($thisFileInfo[5]+1900)) . " " . sprintf( "%02d:%02d",$thisFileInfo[2],$thisFileInfo[1]);
	}
	$strRepHashKey = sprintf('%-60s',$strLogFile) . sprintf('%-20s',$thisModifiedTime);
	$intAdInFeedCntrHash{$strRepHashKey} = $intAdInFeedCntr;

	# ----------------------
	# Process GB Sponsorship
	# ----------------------
	my $strGBUpsellInfo = "GB Sponsorship Data for ($strNewspaper) Feed ($strLogFile)\n\n";
	if (@gbSponsorShipArrayOfHashes) {
		my $intGBUpsellRecCntr = @gbSponsorShipArrayOfHashes;
		my $strSubjectLine     = "GB Sponsorship Data for ($strNewspaper) Feed ($strLogFile) Records ($intGBUpsellRecCntr)";
		   $strGBUpsellInfo    = obtGBSponsorshipProc($strSubjectLine, (not $intPosting), @gbSponsorShipArrayOfHashes );
	}
	DebugPrint("\n\n$strGBUpsellInfo \n");



	DebugPrint("\n\nNotice Error Counts by Error Type:\n");
	foreach my $type (sort keys %errorTypes) {
		$thisFileDataErrors .= "$type\t$errorTypes{ $type }\n";
	}

	#------------------------------------------------------------------------------
	# Prepend All notice errors from this run to the beginning of the summary file
	# use perls inplace editor $^I and the current line number $.
	#------------------------------------------------------------------------------

	my $text_to_prepend = "\n################## No Notice Errors for this Run $strLogFile $strDateStamp $strTimeStamp ##################\n\n\n\n\n";
	if (keys %errorTypes) {
		$text_to_prepend = <<eof;
###### Error Summary for this Run $strLogFile $strDateStamp $strTimeStamp #######\n
Check towards the bottom of this file to see each error in context\n
$thisFileDataErrors
######## End of Errors for $strLogFile $strDateStamp $strTimeStamp #######\n\n\n\n\n
eof
	}

	close SUMMARY;
	{
		local @ARGV = ($strSummaryLogFile);
		local $^I   = '.bac';
		while ( <> ) {
			print "$text_to_prepend\n" if ($. == 1);
			print;
		}
	}
	open SUMMARY, ">>$strSummaryLogFile";
	unlink "$strSummaryLogFile.bac";


	if ( CREATE_IMAGE_ERROR_FEED && ($allBadImageNotices =~ /\S/) ) 
	{
		DebugPrint("---\n$allBadImageNotices\n---\n");
		my $missingImageFile = "$strErrorDir/" . MISSING_IMAGE_FEED_PREFIX . $strLogFile;
		DebugPrint("missing image file: $missingImageFile\n");
		open  MISSINGIMAGEFEED, ">$missingImageFile" or die "unable to open file: $missingImageFile\n";
		print MISSINGIMAGEFEED $allBadImageNotices;
		close MISSINGIMAGEFEED;
	}

	if (MOVE_FEEDFILE_AFTER_RUN || (not $intDebugMode)) { 
		FinishFile( $fileStatus, $strLogFile, FINISHFILE_STOREIN_NEWDIR_NO,  $strLogFile,  FINISHFILE_TIMESTAMP_YES) if ($intPosting);
		#FinishFile($fileStatus, $strLogFile, FINISHFILE_STOREIN_NEWDIR_YES, $strDateStamp, FINISHFILE_TIMESTAMP_NO) if ($intPosting);
	}
	else {
		warn "we skipped finishfile so that we don't have to keep restoring the feed file to rerun it\n";
	}

}# end foreach my $strLogFile ( @feedFiles )

DebugPrint("Report file is: [" . $reportFile . "]\n");

close REPORT;

# ---------------------------------------------------
# Delete the error report file if no errors occurred.
# ---------------------------------------------------
if($intNoErrors)
{
	DebugPrint("No processing errors - deleting error file\n");
	unlink $reportFile;
}

# -------------------------------------
# Change back to the working directory.
# -------------------------------------
chdir($strCurDir);

obtReport();

DebugPrint("\n\nParsing process complete ... goodbye!\n\n");

# -------------------------------------------------
# Close file, directory handles and data connection
# -------------------------------------------------
close SUMMARY;
$data->Close() if ( $intPosting );






########################################## SUBROUTINES #################################################

sub obtExtractFieldsFromFeed 
{
	my $xmlTag;
	$line = "";
	$line .= "\"$strLogFile\"," ;
	$line .= "\"$strDateStamp" . " $strReportDate\"," ;
	$error = "";

	$strCompleteNotice =~ s/<!\[CDATA\[|\]\]>//ig;

	# -----------------------------
	# Get Unique ID - Without this, the ad can never be changed via the feed
	# -----------------------------
	$xmlTag = "UniqueID";
	$strAdId = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	$strAdId =~ s/.*?(.{1,30})/$1/; # use only last 30 chars
	$strAdId =~ s!\'!!g;
	DebugPrint("AD ID        ( $strAdId ) [$strLogFile]\n");
	$line .= "\"$strAdId\"," ;

	# -----------------------------
	# Get Post Date
	# -----------------------------
	$xmlTag = "PostDate";
	$strDeathNoticeDate  = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	DebugPrint("Start Date   ( $strDeathNoticeDate )\n");
	$line .= "\"$strDeathNoticeDate\"," ;

	# -------------------
	# Get Stop Date
	# -------------------
	$xmlTag = "EndDate";
	$strStopDate = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	DebugPrint("EndDate      ( $strStopDate )\n");

	# ------------------------------------------------------------
	# Get payment code
	# ------------------------------------------------------------
	# ***** REMOVE ANY NOTICE TYPES THAT ARE NOT BEING USED *****
	# ------------------------------------------------------------
	$xmlTag = "NoticeType";
	$strNoticeType  = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	given ($strNoticeType)
	{
		if    (/FREE|Courtesy/i ) { $strPaymentCode = PAYMENT_CODE_OBIT_FREE; }
		elsif (/Memoriam/i      ) { $strPaymentCode = PAYMENT_CODE_MEMORIAM;  }
		default            { $strPaymentCode = PAYMENT_CODE_OBIT_PAID; }
	}
	DebugPrint("Payment Code ( $strPaymentCode )\n");
	$line .= "\"$strPaymentCode\"," ;

	$xmlTag = "Email";
    $strEmail = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	#--------------------------------------------------------
	# Email is now validated in sub obtRunSQLIfAppropriate
	# $strEmail = ValidateEmail( $strEmail );
	#--------------------------------------------------------
	$strEmail =~ s/'/''/g;
	DebugPrint("Email        ( $strEmail )\n");

	# --------------------------
	# Get the Funeral Home info
	# --------------------------
	$xmlTag = "FuneralHome";
	$strFuneralHome = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	$strFuneralHomeInfo = "FH = $strFuneralHome " if ( $strFuneralHome );

	$xmlTag = "FuneralHomeAddress";
	$strFuneralHomeAddr = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	$strFuneralHomeInfo .= "FHADDR = $strFuneralHomeAddr " if ( $strFuneralHomeAddr );

	$xmlTag = "FuneralHomeCity";
	$strFuneralHomeCity = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	$strFuneralHomeInfo .= "FHCITY = $strFuneralHomeCity " if ( $strFuneralHomeCity );

	$strFuneralHomeInfo = Trim($strFuneralHomeInfo);
	DebugPrint("Funeral Home Info     ( $strFuneralHomeInfo )\n");

	# --------------------------------
	# Get notice text
	# --------------------------------
	$xmlTag = "Notice";
	$strDeathNotice = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	my $newlinesReplacement = " ";
	   $newlinesReplacement = "<br/><br/>" if (SHOW_NOTICE_LINE_BREAKS);
	$strDeathNotice =~ s!\n+!$newlinesReplacement!gs;
	#DebugPrint("Notice       ( $strDeathNotice )\n");
	# ---------------------------------------------------------
	# Save a copy of strDeathNotice so we can prepend the 
	# newspaper-specific image tag in obtProcessFTPPhotoAndLogo
	# ---------------------------------------------------------
	$strDeathNoticeCopy = $strDeathNotice;

	# ---------------------------------
	# Get Name of Deceased From Notice
	# ---------------------------------
	$xmlTag = "fullname";
	$strDeathNoticeName  = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	# remove space from Mc Donald or Mac Cleod or Van Huesen
	$strDeathNoticeName =~ s/(Ma?c|Van) ([A-Z])/$1$2/;
	# PRESERVE_NAME_ORDER   CHANGE_NAME_ORDER    FIX_CASE_YES  FIX_CASE_NO
	SplitNameTwo($strDeathNoticeName, FIX_CASE_NO, PRESERVE_NAME_ORDER);
	$max_name_length = length $strDeathNoticeName if ((length $strDeathNoticeName) > $max_name_length);
	my $parsed_name = "[$strNamePrefix] [$strFirstName] [$strMiddleName] [$strLastName] [$strNickName]  [$strMaidenName] [$strNameSuffix]";
	$names{$strDeathNoticeName} = $parsed_name;
	$line .= "\"$strDeathNoticeName\"," ;

	# ----------------------------------------------
	# Get photos and logos
	# ----------------------------------------------
	$strImage = "";
	while ( $strCompleteNotice =~ m!(.*?)<Photo>\s*(.*?)\s*</Photo>(.*)!is )
	{
		$strCompleteNotice = $1 . $3;
		$strImage          = $2;
		$intPhotoCount++;
		$strImage = obtFetchImage( $strImage, 'photo' ) if ( $strImage =~ m!^http:! );
		push @photos, $strImage if ($strImage ne "" );
	}

	$strImage = "";
	while ( $strCompleteNotice =~ m!(.*)<Logo>\s*(.*?)\s*</Logo>(.*)!is )
	{
		$strCompleteNotice = $1 . $3;
		$strImage          = $2;
		$intPhotoCount++;
		$strImage = obtFetchImage( $strImage, 'logo'  ) if ( $strImage =~ m!^http:! );
		push @logos, $strImage if ( $strImage ne "" );
	}

	$strImage = "";
	while ( $strCompleteNotice =~ m!(.*)<Icon>\s*(.*?)\s*</Icon>(.*)!is )
	{
		$strCompleteNotice = $1 . $3;
		$strImage          = $2;
		$intPhotoCount++;
		$strImage = obtFetchImage( $strImage, 'icon'  ) if ( $strImage =~ m!^http:! );
		push @icons, $strImage if ( $strImage ne "" );
	}

	# strip out any img tags remaining in the death notice after image extraction
	$strDeathNotice =~ s/<img .*?>//gi;

	# --------
	# Get City
	# --------
	$xmlTag = "City";
	$strCity = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	$strCity = FixName($strCity);
	DebugPrint("City            ( $strCity )\n");

	# --------
	# Get State
	# --------
	$xmlTag = "State";
	$strState = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	DebugPrint("State           ( $strState )\n");

	# ------------------------------------------------------------
	# Set Location Info
	# ------------------------------------------------------------
	# ***** REMOVE ANY PARAMETERS THAT ARE NOT BEING USED *****
	# ------------------------------------------------------------
	# use comma separated values for multiple locations
	# City$chicago,fort worth,milwaukee
	$strLocationInfo = "City\$" . $strCity . "|" if($strCity ne "");
	DebugPrint("strLocationInfo ( $strLocationInfo )\n");

	# -----------------------------------------------
	# Year Born (used only to create $strNoticeYears)
	# -----------------------------------------------
	$xmlTag = "DateBorn";
	$strYearBorn  = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	DebugPrint("Year Born       ( $strYearBorn )\n");

	# ----------------------------------------------------
	# Year Deceased (used only to create $strNoticeYears)
	# ----------------------------------------------------
	$xmlTag = "DateDeceased";
	$strYearDeceased = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	DebugPrint("Year Deceased   ( $strYearDeceased )\n");

	$strNoticeYears = "$strYearBorn - $strYearDeceased" if ($strYearBorn && $strYearDeceased);

	# -----------------------------
	# Get Spotlight flag <Spotlight>Y</Spotlight>
	# -----------------------------
	$xmlTag = "Spotlight";
	$intShowInSpotlight = SHOW_IN_SPOTLIGHT_YES if ( $strCompleteNotice =~ m!<$xmlTag>\s*Y\s*</$xmlTag>!is );
	DebugPrint("Spotlight       ( $intShowInSpotlight )\n");

	# -----------------------------
	# Get Print Post Date
	# -----------------------------
	$dateStartPrint = $strDeathNoticeDate;
	DebugPrint("StartDatePrint( $dateStartPrint )\n");

	# -------------------
	# Get Print Stop Date
	# -------------------
	$dateEndPrint = $strStopDate;
	DebugPrint("EndDatePrint ( $dateEndPrint )\n");

	# -----------------------------------------
	# Get Date of Death
	# -----------------------------------------
	$xmlTag = "DateDeceased";
	$strDateOfDeath = $1 if ( $strCompleteNotice =~ m!<$xmlTag>\s*(.*?)\s*</$xmlTag>!is );
	DebugPrint("Date of Death   ( $strDateOfDeath )\n");

	$strImage = "";
	if ( $strCompleteNotice =~ m!(.*)<muphoto>(.*?)</muphoto>(.*)!is )
	{
		$strCompleteNotice = $1 . $3;
		$strMemUpsellMainPhoto = $2;
	}

	# fail in a nice recognizable way for NS and don't run the SQL
	# my $error   = "Put a nice error message here\n";
	# $fileStatus = CompleteNotice(NOTICE_ERROR, "$strDeathNoticeName (SourceAdId: $strAdId)", $error );
	# $intSkipAd  = TRUE;

}# end sub ExtractFromFeed


sub obtProcessFTPPhotoAndLogo
{
	my $photos  = shift;
	my $logos   = shift;
	my $newspaper = shift;

	DebugPrint("Photos = @$photos\n");
	DebugPrint("Logos  = @$logos\n");

	my $numMissingImageKeys = keys %missing_images;
	
	# ------------------
	# Process the photos
	# ------------------
	my $imageCount = 0;
	my $imageTags = "";

	DebugPrint("In obtProcessFTPPhotoAndLogo - newspaper is: $newspaper\n");

	foreach my $photo (@$photos)
	{
		$photo = Trim($photo);
		next if (not $photo);

		# use date stamp here, not timestamp, so that the source hash
		# doesn't change when an identical update comes in within the same day
		my $newPhoto = $photo;
		$newPhoto =~ s!(\.(gif|jpe?g|tiff?|eps|png))?$!_$strDateStamp\.jpg!i;
		$newPhoto =~ s/[^A-Z\d\.\-\_]//ig; # allow only whitelisted chars

		DebugPrint("New Photo Name = " . $newPhoto . "\n");

		$strProdPhotoDir = "$strImageRoot/Cobrands/$newspaper/Photos";
		$strPhotoWebRoot = "/Images/Cobrands/$newspaper/Photos/";

		DebugPrint("strProdPhotoDir = [$strProdPhotoDir]\n");
		DebugPrint("strPhotoWebRoot = [$strPhotoWebRoot]\n");

		my $moveImageSourcePathFile = "$strNoticeDir/Photos/$photo";
		my $moveImageTargetPathFile = "$strPhotoSaveDir/$photo";
		my $copyImageSourcePathFile = "$strPhotoSaveDir/$photo";
		my $copyImageTargetPathFile = "$strProdPhotoDir/$newPhoto";

		DebugPrint("moveImageSourcePathFile = [" . $moveImageSourcePathFile . "]\n");
		DebugPrint("moveImageTargetPathFile = [" . $moveImageTargetPathFile . "]\n");
		DebugPrint("copyImageSourcePathFile = [" . $copyImageSourcePathFile . "]\n");
		DebugPrint("copyImageTargetPathFile = [" . $copyImageTargetPathFile . "]\n");


#		my $moveImageSourcePathFile = "$strNoticePhotoDir/$photo";
#		my $moveImageTargetPathFile = "$strPhotoSaveDir/$newspaper/$photo";
#		my $copyImageSourcePathFile = "$strPhotoSaveDir/$newspaper/$photo";
#		my $copyImageTargetPathFile = "$strProdPhotoDir/$newspaper/$newPhoto";
#
#		DebugPrint("moveImageSourcePathFile = $moveImageSourcePathFile\n");
#		DebugPrint("moveImageTargetPathFile = $moveImageTargetPathFile\n");
#		DebugPrint("copyImageSourcePathFile = $copyImageSourcePathFile\n");
#		DebugPrint("copyImageTargetPathFile = $copyImageTargetPathFile\n");

		$imageCount++;
		$strRepHashKey = sprintf('%-70s',$strAdId."+".$strLastName) . sprintf('%-8s',"Photo") . sprintf('%-8s',$imageCount);
		if    (-z $moveImageSourcePathFile ) { $missing_images{$strRepHashKey} = "$photo (exists, but 0 bytes) ";}
		elsif (-e $moveImageSourcePathFile ) { $found_images{$strRepHashKey}   = "$photo ";}
		elsif (-e $moveImageTargetPathFile ) { $found_images{$strRepHashKey}   = "$photo";}
		else                                 { $missing_images{$strRepHashKey} = "$photo";}

		# ----------------------
		# Convert / resize image
		# ----------------------
		my $convertCmd = "Convert " . CONVERT_PHOTO_OPTIONS . " \"$copyImageSourcePathFile\" \"$copyImageTargetPathFile\" ";

		# -----------------------------------------------
		# Move the image to the proper directory.
		# -----------------------------------------------
		if( $intPosting )
		{
			
			if($newspaper eq 'SaltLakeTribune')
			{
				copy( ($moveImageSourcePathFile), ($moveImageTargetPathFile) ) or DebugPrint("Copy Failed...$!\n");
				#copy( ($copyImageSourcePathFile), ($copyImageTargetPathFile) ) or DebugPrint("Copy Failed...$!\n");
				system $convertCmd;
				DebugPrint("Converting...$!\n");
			}
			else
			{
				$strMainPhoto = "";
				move( ($moveImageSourcePathFile), ($moveImageTargetPathFile) ) or DebugPrint("Move Failed...$!\n");
				#copy( ($copyImageSourcePathFile), ($copyImageTargetPathFile) ) or DebugPrint("Copy Failed...$!\n");
				system $convertCmd;
				DebugPrint("Converting...$!\n");
			}
		}

		#-----------------------------
		# Site Redesign: Populate
		#-----------------------------
		if (ENABLE_MAIN_PHOTO && (!$strMainPhoto)) {
			if( $intPosting ) {
				DebugPrint("Getting size of $copyImageTargetPathFile\n");
				($intMainPhotoWidth, $intMainPhotoHeight) = imgsize($copyImageTargetPathFile);
			} else {
				DebugPrint("not posting - source path file Getting size of $moveImageSourcePathFile\n");
				($intMainPhotoWidth, $intMainPhotoHeight) = imgsize($moveImageSourcePathFile);
			}
			# set to 0 if not defined
			$intMainPhotoWidth  //= 0;
			$intMainPhotoHeight //= 0;
			DebugPrint("PhotoSize [W, H] = [$intMainPhotoWidth, $intMainPhotoHeight]\n");
			if ($intMainPhotoWidth && $intMainPhotoHeight) {
				$strMainPhoto = $newPhoto;
				$strRepHashKey = sprintf('%-40s',$strNewspaper) . sprintf('%-60s',$strAdId."+".$strLastName) . sprintf('%-40s', $strMainPhoto) . sprintf('%-7s',$intMainPhotoWidth) . sprintf('%-7s',$intMainPhotoHeight);;
				$MainPhotoHash{$strRepHashKey} = $copyImageTargetPathFile;
			}
		}

		DebugPrint("Move Photo = ".$moveImageSourcePathFile." ".$moveImageTargetPathFile."\n");
		#DebugPrint("Copy Photo = ".$copyImageSourcePathFile." ".$copyImageTargetPathFile."\n");
		DebugPrint("Convert [" . $convertCmd . "]\n");

		DebugPrint("strPhotoWebRoot = $strPhotoWebRoot\n");
		$imageTags .= "<IMG SRC=\"$strPhotoWebRoot/$newPhoto\" lgyOrigName=\"$photo\" ALIGN=\"LEFT\" vspace=\"4\" hspace=\"10\" style=\"max-width:130px;\">";
	}# end foreach $photo (@$photos)
	# ----------------------------------------------------------------------------------
	# Uncomment this line of code if:
	#   1.  The affiliate is using icons but is not identifying image types in the feed
	#   2.  The affiliate is using icons but we're unable to distinguish the image type 
	#       using other means such as file naming convention.
	# ---------------------------------------------
	#$imageTags = "<!-- DisplayFullObituaryText -->" . $imageTags;
	# ----------------------------------------------------------------------------------

	$strDeathNotice = $imageTags . $strDeathNoticeCopy;
	
	#----------------------------------
	# Process the logos
	#----------------------------------
	$imageCount = 0;
	foreach my $logo (@$logos)
	{
		next if (not $logo);

		my $newLogo = $logo;
		$newLogo =~ s/\.(gif|jpe?g|tiff?|eps|png)/\.jpg/gis;
		$newLogo =~ s/&/_/g;
		$newLogo =~ s/[^A-Z\d\.\-\_]//ig;

		my $moveImageSourcePathFile = "$strNoticePhotoDir/$logo";
		my $moveImageTargetPathFile = "$strPhotoSaveDir/$logo";
		my $copyImageSourcePathFile = "$strPhotoSaveDir/$logo";
		my $copyImageTargetPathFile = "$strProdLogoDir/$newLogo"; # add .jpg if you are converting from another format
		$imageCount++;
		$strRepHashKey = sprintf('%-70s',$strAdId."+".$strLastName) . sprintf('%-8s',"Logo") . sprintf('%-8s',$imageCount);
		if    (-z $moveImageSourcePathFile)  { $missing_images{$strRepHashKey} = "$logo (exists, but 0 bytes) ";}
		elsif (-e $moveImageSourcePathFile ) { $found_images{$strRepHashKey}   = "$logo ";}
		elsif (-e $moveImageTargetPathFile ) { $found_images{$strRepHashKey}   = "$logo ";}
		else                                 { $missing_images{$strRepHashKey} = "$logo ";}

		# ---------------------------
		# Convert the image to a jpg
		# ---------------------------
		my $strConvertCmd = "Convert " . CONVERT_LOGO_OPTIONS . " \"$copyImageSourcePathFile\" \"$copyImageTargetPathFile\" ";

		# -----------------------------------------------
		# Move the logo image to the proper directory.
		# -----------------------------------------------
		if( $intPosting )
		{
			move( ($moveImageSourcePathFile), ($moveImageTargetPathFile) );
			#copy( ($copyImageSourcePathFile), ($copyImageTargetPathFile) );
			system $strConvertCmd;
		}
		DebugPrint("Move Logo = $moveImageSourcePathFile $moveImageTargetPathFile\n");
		DebugPrint("Copy Logo = $copyImageSourcePathFile $copyImageTargetPathFile\n");
		#DebugPrint("Convert [" . $strConvertCmd . "]\n");

		$strDeathNotice .= "<BR/><CENTER><IMG SRC=\"$strLogoWebRoot/$newLogo\" ALT=\"logo\" BORDER=\"0\"/></CENTER>";

	}# end foreach $strLogo (@strLogoLine)

	$missingImage = TRUE if ($numMissingImageKeys < keys %missing_images);

}# end sub obtProcessFTPPhotoAndLogo


sub obtProcessFTPIcon
{
	my $icons   = shift;
	my $imageCount = 0;
	my $iconTags = "";
	my $iconTag = "";
	my $icon = "";

	DebugPrint("Icons  = @$icons\n");
	
	my $numMissingImageKeys = keys %missing_images;

	if(-s $strConfigFile)
	{
		# -----------------------------------
		# Process icons for an NGO affiliate.
		# -----------------------------------
	#	DebugPrint("\niconMap:\n");
	#	while ( my ($key, $value) = each(%iconMap) ) {
	#        print "$key => $value\n";
	#    }
	#	DebugPrint("\n");
		
		foreach $icon (@$icons)
		{
			next if (not $icon);

			# --------------------------------------------
			# Strip the extraneous text off the image 
			# reference and use the result as the Icon reference. 
			# --------------------------------------------	
			my $strIconReference = $icon;
			DebugPrint("Icon reference is [" . $strIconReference . "]\n");
			$strIconReference = lc $strIconReference;
			DebugPrint("Icon reference is [" . $strIconReference . "]\n");
			
			# ----------------------------------------
			# Now map the image name we've extracted
			# to the Icon Code that will be passed
			# in the stored procedure.  Look up the 
			# name of the icon that resides in the library
			# and use that to build the image link.
			# Report any icon image references that 
			# can't be mapped.
			# ----------------------------------------
			if(exists $affiliateIcons{$strIconReference})
			{	
				# ---------------------------------------------
				# Get the icon code (or codes) associated with 
				# the icon reference in the feed. 
				# ---------------------------------------------
				if ($strIconCodes ne "") {
					$strIconCodes = $strIconCodes . ',' . $affiliateIcons{$strIconReference};
				}
				else {
				     $strIconCodes = $affiliateIcons{$strIconReference};
				}

				DebugPrint("Icon match found!\n");
				DebugPrint("Icon code = [" . $strIconCodes . "]\n");
			}
			else
			{
				# ------------------------------------------------------------
				# There was no entry in the affiliateIcons hash that matched 
				# the reference in the feed. Try and find an image file with 
				# the feed reference and use that instead.
				# ------------------------------------------------------------
				DebugPrint("No icon match found!\n");
				$strRepHashKey = sprintf('%-70s',$strAdId."+".$strLastName) . sprintf('%-8s',"Icon") . sprintf('%-8s',$imageCount);
				$intUnmappedIcon = TRUE;
				$strRepHashKey = sprintf('%-70s',$strAdId."+".$strLastName) . sprintf('%-8s',"Icon") . sprintf('%-8s',$imageCount);
				my $moveImageSourcePathFile = "$strNoticePhotoDir/$icon";
				my $moveImageTargetPathFile = "$strPhotoSaveDir/$icon";
				my $copyImageSourcePathFile = "$strPhotoSaveDir/$icon";
				my $copyImageTargetPathFile = "$strProdLogoDir/$icon"; # add .jpg if you are converting from another format
				$imageCount++;
				$strRepHashKey = sprintf('%-70s',$strAdId."+".$strLastName) . sprintf('%-8s',"Icon") . sprintf('%-8s',$imageCount);
				if    (-z $moveImageSourcePathFile)  { $missing_images{$strRepHashKey} = "$icon (exists, but 0 bytes) ";}
				elsif (-e $moveImageSourcePathFile ) { $found_images{$strRepHashKey}   = "$icon ";}
				elsif (-e $moveImageTargetPathFile ) { $found_images{$strRepHashKey}   = "$icon ";}
				else                                 { $missing_images{$strRepHashKey} = "$icon ";}

				# ---------------------------
				# Convert the image to a jpg
				# ---------------------------
				my $strConvertCmd = "Convert " . CONVERT_ICON_OPTIONS . " \"$copyImageSourcePathFile\" \"$copyImageTargetPathFile\" ";

				# -----------------------------------------------
				# Move the icon image to the proper directory.
				# -----------------------------------------------
				if( $intPosting )
				{
					move( ($moveImageSourcePathFile), ($moveImageTargetPathFile) );
					#copy( ($copyImageSourcePathFile), ($copyImageTargetPathFile) );
					system $strConvertCmd;
				}
				DebugPrint("Move Icon = $moveImageSourcePathFile $moveImageTargetPathFile\n");
				#DebugPrint("Copy Icon = $copyImageSourcePathFile $copyImageTargetPathFile\n");
				DebugPrint("Convert [" . $strConvertCmd . "]\n");
				$iconTag = "<IMG SRC=\"$strLogoWebRoot/$icon\" ALT=\"logo\" BORDER=\"0\"/>";
				$iconTags .=  $iconTag;
				$error = "Unable to map icon reference $strIconReference to icon library\n";
				$error =~ s/\"//gis;
				$error = "\"$error\",";
				$errorTypes{$strDataError}++;
				if(SEND_UNMAPPED_ICON_ALERT)
				{
					$fileStatus = CompleteNotice(NOTICE_ERROR, "$strDeathNoticeName (SourceAdId: $strAdId)", $error );
				} 

			}
		}# end foreach icon
		
		# ------------------------------------------------
		# There could be multiple icon codes so split
		# the value in strIconCodes into an array.
		# Iterate through the array and get the name 
		# of the icon in the library using the icon code(s).
		# Build the iconTags using the file name and append
		# to the notice text. 
		# ------------------------------------------------
		my $iconLibraryFileName;
		$iconTag = "";
		my @icons = split /,/, $strIconCodes;
		DebugPrint("strIconCodes: $strIconCodes\n");
		foreach (@icons) 
		{
			my $icon_code = $_;
			DebugPrint("icon code is: [" . $icon_code . "]\n");
			$iconLibraryFileName = "";
			$iconLibraryFileName = $iconMap{$icon_code};
			if($iconLibraryFileName ne "")
			{
				DebugPrint("Icon file name = [" . $iconLibraryFileName . "]\n");
				$iconTags .=  "<IMG SRC=\"$strIconWebRoot/$iconLibraryFileName\" ALT=\"logo\" BORDER=\"0\"/>";
			}
			else
			{
				DebugPrint("No icon image file found!\n");
				$strRepHashKey = sprintf('%-70s',$strAdId."+".$strLastName) . sprintf('%-8s',"Icon") . sprintf('%-8s',$imageCount);
				$intUnmappedIcon = TRUE;
				$unmapped_icons{$strRepHashKey} = $icon;
				$strIconCodes = "";
				$error = "Unable to locate image file for icon code $icon_code";
				$error =~ s/\"//gis;
				$error = "\"$error\",";
				$errorTypes{$strDataError}++;
				if(SEND_UNMAPPED_ICON_ALERT)
				{
					$fileStatus = CompleteNotice(NOTICE_ERROR, "$strDeathNoticeName (SourceAdId: $strAdId)", $error );
				} 
			}
		}

		$strDeathNotice .= '<BR/><CENTER>' . $iconTags . '</CENTER>';
	}
	else
	{
		#----------------------------------
		# Process the icons for non-NGO affiliate.
		# Keep the original filename, like logos
		# Convert them with icon size restrictions
		#----------------------------------
		foreach $icon (@$icons)
		{
			$intUnmappedIcon = TRUE;

			next if (not $icon);

			my $newIcon = $icon;
			$newIcon =~ s/\.(gif|jpe?g|tiff?|eps|png)/\.jpg/gis;
			$newIcon =~ s/[^A-Z\d\.\-\_]//ig;

			my $moveImageSourcePathFile = "$strNoticePhotoDir/$icon";
			my $moveImageTargetPathFile = "$strPhotoSaveDir/$icon";
			my $copyImageSourcePathFile = "$strPhotoSaveDir/$icon";
			my $copyImageTargetPathFile = "$strProdLogoDir/$newIcon"; # add .jpg if you are converting from another format
			$imageCount++;
			$strRepHashKey = sprintf('%-70s',$strAdId."+".$strLastName) . sprintf('%-8s',"Icon") . sprintf('%-8s',$imageCount);
			if    (-z $moveImageSourcePathFile)  { $missing_images{$strRepHashKey} = "$icon (exists, but 0 bytes) ";}
			elsif (-e $moveImageSourcePathFile ) { $found_images{$strRepHashKey}   = "$icon ";}
			elsif (-e $moveImageTargetPathFile ) { $found_images{$strRepHashKey}   = "$icon ";}
			else                                 { $missing_images{$strRepHashKey} = "$icon ";}

			# ---------------------------
			# Convert the image to a jpg
			# ---------------------------
			my $strConvertCmd = "Convert " . CONVERT_ICON_OPTIONS . " \"$copyImageSourcePathFile\" \"$copyImageTargetPathFile\" ";

			# -----------------------------------------------
			# Move the logo image to the proper directory.
			# -----------------------------------------------
			if( $intPosting )
			{
				move( ($moveImageSourcePathFile), ($moveImageTargetPathFile) );
				#copy( ($copyImageSourcePathFile), ($copyImageTargetPathFile) );
				system $strConvertCmd;
			}
			DebugPrint("Move Icon = $moveImageSourcePathFile $moveImageTargetPathFile\n");
			#DebugPrint("Copy Icon = $copyImageSourcePathFile $copyImageTargetPathFile\n");
			DebugPrint("Convert [" . $strConvertCmd . "]\n");
			$iconTags .=  "<IMG SRC=\"$strLogoWebRoot/$newIcon\" ALT=\"logo\" BORDER=\"0\"/>";

		}# end foreach icon
		if($iconTags)
		{
			$strDeathNotice .= '<BR/><BR/><CENTER>' . $iconTags . '</CENTER>';
		}
	}

	if($intUnmappedIcon)
	{
		$strDeathNotice .= "<!-- DisplayFullObituaryText -->";
	}

}# end sub obtProcessFTPIcon


sub obtInitAdVars
{
	$strAdId              = "";
	$strDeathNoticeDate   = "";
	$strStopDate          = "";
	$strCity              = "";
	$strState             = "";
	$strLocationInfo      = "";
	$strCounty            = "";
	$strDeathNoticeName   = "";
	$strPaymentCode       = PAYMENT_CODE_OBIT_PAID;
	$strNoticeType        = "";
	$strYearBorn          = "";
	$strYearDeceased      = "";
	$strNoticeYears       = "";
	$intShowInSpotlight   = SHOW_IN_SPOTLIGHT_NO;
	$strDeathNotice       = "";
	$strImage             = "";
	$strEmail             = "";
	$strPublishedBy       = "";
	$strNewspaperGroup    = "";
	$strFuneralHome       = "";
	$strFuneralHomeId     = "";
	$strFuneralHomeAddr   = "";
	$strFuneralHomeCity   = "";
	$strFuneralHomeState  = "";
	$strFuneralHomeZip    = "";
	$strFuneralHomePhone  = "";
	$strFuneralHomeInfo   = "";
	@photos               = ();
	@logos                = ();
	@icons                = ();
	$intPhotoCount        = 0;
	$intSkipAd            = FALSE;
	$strMainPhoto         = "";
	$intMainPhotoWidth    = 0;
	$intMainPhotoHeight   = 0;
	$dateStartPrint       = "";
	$dateEndPrint         = "";
	$strSponsorName       = "";
	$strSponsorEmail      = "";
	$intSponsorshipLength = "";
	$intNoticeExpirationDays = "";
	%errorTypes           = ();
	$thisFileDataErrors   = "";
	$missingImage         = FALSE;
	$hasMemoriamUpsell    = FALSE;
	$deleteMemoriamUpsell = FALSE;
	$strDateOfDeath       = "";
	$strMemUpsellText     = "";
	$strIconCodes         = "";
	$intUnmappedIcon      = FALSE;
	$strDataError         = "";
}


sub obtCleanupDeathNoticeCharacters
{
	$strDeathNotice =~ s/<!\[CDATA\[|\]\]>//gi;
	$strDeathNotice =~ s/\s+/ /g;
	$strDeathNotice = "<!-- $strFuneralHomeInfo -->" . $strDeathNotice if ( $strFuneralHomeInfo );
	$strDeathNotice = "<!-- $strDeathNoticeName -->$strDeathNotice<br/>";
	$strDeathNotice =~ s/\'+/''/g;
	$strDeathNotice = AutoHyperlink($strDeathNotice);
}


sub cmnCleanUpDataFeed {
	my $feed = shift;

	$feed =~ s/\x00//gi;
	$feed =~ s/&amp;/&/gi;
	$feed =~ s/&#33;/\!/gis;
	$feed =~ s/&#34;/\"/gis;
	$feed =~ s/&#35;/\#/gis;
	$feed =~ s/&#36;/\$/gis;
	$feed =~ s/&#37;/\%/gis;
	$feed =~ s/&#38;/\&/gis;
	$feed =~ s/&#39;/\'/gis;
	$feed =~ s/&#40;/\(/gis;
	$feed =~ s/&#41;/\)/gis;
	$feed =~ s/&#42;/\*/gis;
	$feed =~ s/&#43;/\+/gis;
	$feed =~ s/&#44;/\,/gis;
	$feed =~ s/&#45;/\-/gis;
	$feed =~ s/&#46;/\./gis;
	$feed =~ s/&#47;/\//gis;
	$feed =~ s/&#58;/\:/gis;
	$feed =~ s/&#59;/\;/gis;
	$feed =~ s/&#60;/\</gis;
	$feed =~ s/&#61;/\=/gis;
	$feed =~ s/&#62;/\>/gis;
	$feed =~ s/&#63;/\?/gis;
	$feed =~ s/&#91;/\[/gis;
	$feed =~ s/&#92;/\\/gis;
	$feed =~ s/&#93;/\]/gis;
	$feed =~ s/&#94;/\^/gis;
	$feed =~ s/&#95;/\_/gis;
	$feed =~ s/&#96;/\`/gis;
	$feed =~ s/&#821[67]\;/\'/gi;
	$feed =~ s/&#822[01]\;/\"/gi;
	$feed =~ s/&quot;/\"/gi;
	$feed =~ s/&(ld|rd)?quo;/\"/gi;
	$feed =~ s/&(ls|rs)?quo;/\'/gi;
	$feed =~ s/&apos;/\'/gi;
	$feed =~ s/&ndash;/-/gi;
	$feed =~ s/&lt;/</gi;
	$feed =~ s/&gt;/>/gi;
	$feed =~ s/[“”]/\"/g;
	$feed =~ s/[‘’]/\'/g;

	return $feed;

}# end sub cmnCleanUpDataFeed


sub obtRunSQLIfAppropriate
{
	my $newspaper = shift;

	#----------------------------------------
	# Report: Populate hashes and other vars.
	#----------------------------------------
	$strRepHashKey = sprintf('%-40s',$strNewspaper) . sprintf('%-40s',$strAdId);
	$intAdIdCntr{$strRepHashKey}++;

	$strRepHashKey = sprintf('%-40s',$strNewspaper) . sprintf('%-40s',$strNoticeType) . sprintf('%-30s',$strPaymentCode);
	$intNoticeTypeCntr{$strRepHashKey}++;

	my $startDateStamp = $strDeathNoticeDate;
	if ($strDeathNoticeDate =~ m!\s*(\d+)/(\d+)/(?:\d\d)?(\d\d)\s*!) 
	{
		my ($mon, $day, $year) = ($1, $2, $3);
		$mon  =~ s!^(\d)$!0$1!;
		$day  =~ s!^(\d)$!0$1!;
		$year =~ s!^(\d\d)$!20$1!;
		$startDateStamp = "$year$mon$day";
	}
	my $stopDateStamp  = $strStopDate;
	if ($strStopDate =~ m!\s*(\d+)/(\d+)/(?:\d\d)?(\d\d)\s*!) 
	{
		my ($mon, $day, $year) = ($1, $2, $3);
		$mon  =~ s!^(\d)$!0$1!;
		$day  =~ s!^(\d)$!0$1!;
		$year =~ s!^(\d\d)$!20$1!;
		$stopDateStamp = "$year$mon$day";
	}
	$dateStamps{$stopDateStamp}  = 1;
	$dateStamps{$startDateStamp} = 1;
	my $strNoticeLink = "http://afstage.legacy.com/obituaries/$strNewspaper/obituary-browse.aspx" .
		"?Startdate=$startDateStamp&Enddate=$stopDateStamp&entriesperpage=50";
	$strRepHashKey = sprintf('%-20s', $strDeathNoticeDate) . sprintf('%-20s', $strStopDate) . $strNoticeLink;
	$dateRangeLinks{$strRepHashKey}++;

	$strRepHashKey = sprintf('%-40s',$strNewspaper) . sprintf('%-20s', $strDeathNoticeDate) . sprintf('%-20s', $strStopDate);
	$dateRangeCount{$strRepHashKey}++;

	if (($strDeathNoticeName =~ m!([^a-z\'\"\(\)\.\-,\s])!i)
	|| ($strLastName =~ /^\s*$/)
	|| ($strFirstName =~ /^\s*$/)
	|| ($strLastName  =~ /Get_name_from_notice_text/)
	|| ($strFirstName =~ /Get_name_from_notice_text/))
	{
		$strRepHashKey = sprintf('%-60s',$strLogFile) . sprintf('%-40s',$strAdId) . sprintf('%-30s',$strFirstName) . sprintf('%-30s',$strLastName);
		$badNames{$strRepHashKey}++;
	}
	if ($strEmail) {
		$strRepHashKey = sprintf('%-60s',$strLogFile)  . sprintf('%-25s',$strAdId)  . substr(sprintf('%-60s',$strEmail),0,60);
		$intValidatedEmailCntr{$strRepHashKey} = "";
		$strEmail = ValidateEmail($strEmail);
		$intValidatedEmailCntr{$strRepHashKey} = $strEmail;
		$intEmailCntr++;
	}
	$intAdInFeedCntr++;


	#----------------------------------------------------------------
	#  strNewspaperGroup don't even put it in the SQL if it's blank.
	#"\@NewspaperGroup='" . $strNewspaperGroup  . "', " .
	#----------------------------------------------------------------
   my $newspaperGroupParam = "";
      $newspaperGroupParam = "\@NewspaperGroup='$strNewspaperGroup', " if ($strNewspaperGroup);

   my $dateOfDeathParam    = "";
      $dateOfDeathParam    = "\@DateOfDeath='$strDateOfDeath', " if ($strDateOfDeath);

   my $noticeExpirationDaysParam = "";
      $noticeExpirationDaysParam = "\@NoticeExpirationDays='$intNoticeExpirationDays', " if ($intNoticeExpirationDays);

   my $sponsorshipLengthParam    = "";
      $sponsorshipLengthParam    = "\@GuestbookExpirationDays='$intSponsorshipLength', " if ($intSponsorshipLength);

   my $dateStartPrintParam = "";
      $dateStartPrintParam = "\@DateStartPrint = '$dateStartPrint', " if ($dateStartPrint);

   my $dateEndPrintParam   = "";
      $dateEndPrintParam   = "\@DateEndPrint = '$dateEndPrint', " if ($dateEndPrint);

	push @notices, "$strAdId,$intSponsorshipLength,$strSponsorName,$strSponsorEmail,$intNoticeExpirationDays";

	#-----------------------------
	# Site Redesign: Use in SQL
	#-----------------------------
	my $strSQL = <<eof;
EXECUTE spInsertNewspaperNoticeWithPhoto
 \@NamePrefix     = '$strNamePrefix',
 \@FirstName      = '$strFirstName',
 \@MiddleName     = '$strMiddleName',
 \@LastName       = '$strLastName',
 \@NickName       = '$strNickName',
 \@MaidenName     = '$strMaidenName',
 \@NameSuffix     = '$strNameSuffix',
 \@State          = '$strState',
 \@City           = '$strCity',
 \@LocationInfo   = '$strLocationInfo',
 \@CreateDate     = '$strDeathNoticeDate',
 \@StopDate       = '$strStopDate',
 \@Newspaper      = '$newspaper',
 \@Notice         = '$strDeathNotice',
 \@PaymentCode    = '$strPaymentCode',
 \@Email          = '$strEmail',
 \@PublishedBy    = '$strPublishedBy',
 $newspaperGroupParam
 $dateOfDeathParam
 \@NoticeYears    = '$strNoticeYears',
 \@ShowInSpotlight= $intShowInSpotlight,
 \@MainPhoto      = '$strMainPhoto',
 \@MainPhotoHeight= '$intMainPhotoHeight',
 \@MainPhotoWidth = '$intMainPhotoWidth',
 \@IconCodes      = '$strIconCodes',
 $noticeExpirationDaysParam
 $sponsorshipLengthParam
 \@SponsorMessage = '$strSponsorName', 
 \@SponsorEmail   = '$strSponsorEmail', 
 \@AllowUpdatesToNameFields = '$intAllowNameUpdate',
 $dateStartPrintParam
 $dateEndPrintParam
 \@FileName       = '$strAdId'
eof

	my $singleLineDebugSQL = TRUE;
	$strSQL =~ s! +|\n+! !g if ($singleLineDebugSQL);
	DebugPrint("SQL = $strSQL\n\n");

	# ----------------------------------
	# Only run the SQL if we are posting
	# ----------------------------------
	if ( $intPosting && $data->Sql($strSQL) )
	{
		# we fall through only if the sql was run and there was an error
		$strDataError = $data->Error();
		print         "$0\n $strDataError \nSQL = (" . $strSQL . ")\n";
		print SUMMARY "$0\n $strDataError \nSQL = (" . $strSQL . ")\n";
		if ($strDataError =~ /Incorrect syntax near '\)'/i ) {
			$strDataError .= "\nHave funeralhome\@legacy.com check Funeral home search clauses.\n";
		}
		$error = $strDataError;
		$error =~ s/\"//gis;
		$error = "\"$error\",";
		$errorTypes{$strDataError}++;
		$fileStatus = CompleteNotice(NOTICE_ERROR, "$strDeathNoticeName (SourceAdId: $strAdId)", $strDataError );
	}


	my $intPersonID = "";
	if( $intPosting && $data->FetchRow() )
	{
		$intPersonID = $data->Data('PersonID');
		DebugPrint("PersonId ($intPersonID)\n");
	}
}


sub obtLoadIconMap
{
	# -----------------------------------------------------
	# Read in the icon config file.  This will provide us
	# with the list of references the affiliate will use in 
	# the feed and the appropriate icon code
	# -----------------------------------------------------
	my $strIconRefAndCode = "";
	my $strLoadIconReference = "";
	my $strLoadIconCodes = "";
	my @CompleteIconList = ();
	my @tempLoadIconCodes = ();
	my @LoadIconCodes = ();
	my $strAffiliateIconCodeList = "";
	my $SQL = "";
	undef my $ODBCLocal;
	my $strCode = "";
	my $strName = "";

	
	# -------------------------------------------------
	# Open the config file and read it into the array.
	# -------------------------------------------------
	DebugPrint("Current working directory is [" . $strCurDir . "]\n");
	$strConfigFile = "$strCurDir/$strNewspaper" . "_IconConfig.txt";	
	DebugPrint("strConfigFile = [" . $strConfigFile . "]\n");

	open ICONFILE, "<$strConfigFile" || die "Config file open failed $!\n";
	@CompleteIconList = <ICONFILE>;
	close ICONFILE;

	# --------------------------------------------------------
	# Iterate through the array created by the config file read.
	# Split the icon references and icon codes, and load them
	# into the $affiliateIcons hash.  The $affiliateIcons hash
	# will be used later on in the obtProcessFTPPhotoAndLogo sub. 
	# It stores the icon codes to be passed to the 
	# spInsertNewspaperNoticeWithPhoto Stored Procedure.  The codes
	# will also be used to determine the associated icon file name 
	# in the obtProcessFTPPhotoAndLogo sub.
	# --------------------------------------------------------
	foreach (@CompleteIconList) 
	{
		$strIconRefAndCode = Trim($_);
		DebugPrint("IconRefAndCode = [" . $strIconRefAndCode . "]\n");
		($strLoadIconReference, $strLoadIconCodes) = split /=/, $strIconRefAndCode;
		$strLoadIconReference = lc Trim($strLoadIconReference);
		$strLoadIconCodes = lc Trim($strLoadIconCodes);
		DebugPrint("Icon Reference = [" . $strLoadIconReference . "]\n");
		DebugPrint("Icon Codes = [" . $strLoadIconCodes . "]\n");
		$affiliateIcons{$strLoadIconReference} = $strLoadIconCodes;
		# ----------------------------------------------------
		# There could be multiples of the same icon code, and we only
		# want to include one instance of each code in the string we're 
		# passing to the stored procedure.  For each icon code we find 
		# check the @LoadIconCodes array and only add it if it's 
		# not already there.
		# ----------------------------------------------------
		@tempLoadIconCodes = split /,/, $strLoadIconCodes;
		foreach my $checkval (@tempLoadIconCodes) 
		{
			#DebugPrint("checkval is [" . $checkval . "]\n");
			push(@LoadIconCodes, $checkval) unless(scalar grep {/^$checkval$/} @LoadIconCodes);
		}
	}
	
	# --------------------------------------------
	# Dump the contents of the array into the string
	# we're passing to the stored procedure and format
	# it for the query.  If the @LoadIconCodes array 
	# is empty pass an empty string to the stored 
	# procedure to return everything in tblIcon.
	# --------------------------------------------
	foreach (@LoadIconCodes) 
	{
		my $code = $_;
#		DebugPrint("$code\n");
		$strAffiliateIconCodeList .= "$code,";
	}
	$strAffiliateIconCodeList = "'" . $strAffiliateIconCodeList . "'";

	# -------------------------------------
	# Get rid of the trailing comma.
	# -------------------------------------
	$strAffiliateIconCodeList =~ s/(.*),/$1/is;
	DebugPrint("\nstrAffiliateIconCodeList = [" . $strAffiliateIconCodeList . "]\n");

	#&spGetIconsLocalDBHandle($strAffiliateIconCodeList);

	#----------------
	# Open local DB
	#----------------
	if (not ( $ODBCLocal = OpenDB($strConnStr) ))
	{
		print SUMMARY "unable to open a DB connection with '$strConnStr'\n";
		die           "unable to open a DB connection with '$strConnStr'\n";
	}

	# ---------------------------------------------------
	# Call the spGetIcons stored procedure to get the 
	# icon codes and their associated file names.
	# ---------------------------------------------------
	$SQL = "EXECUTE spGetIcons " .
			"\@CodeList="  . $strAffiliateIconCodeList;

	DebugPrint("strSQL = [" . $SQL . "]\n");

	if ( $ODBCLocal->Sql($SQL) )
	{
		# we fall through only if the sql was run and there was an error
		my $strDataError = $ODBCLocal->Error();
		print         "$0\n $strDataError \nSQL = (" . $SQL . ")\n";
		print SUMMARY "$0\n $strDataError \nSQL = (" . $SQL . ")\n";
		$error = $strDataError;
		$error =~ s/\"//gis;
		$errorTypes{$strDataError}++;
		$fileStatus = CompleteNotice(NOTICE_ERROR, "$strDeathNoticeName (SourceAdId: $strAdId)", $strDataError );
	}

	# ---------------------------------------------
	# Get the results of the query and load into 
	# the iconMap hash.
	# ---------------------------------------------
	while( $ODBCLocal->FetchRow() )
	{
		$strCode = "";
		$strName = "";
		$strCode = $ODBCLocal->Data('Code');
		$strName = $ODBCLocal->Data('FileName');
		DebugPrint("Icon Code ($strCode)\n");
		DebugPrint("File Name ($strName)\n");
		$iconMap{$strCode} = $strName;
	}

	$ODBCLocal->Close();
}


#---------------------
# Report: Print Report, Display stats for these batch of feeds.
#---------------------
sub obtReport
{
	my $intFound         =  FALSE;
	my $intSpacing       = 0;
	my $intRecordCounter = 0;
	my $intGrandTotalAds = 0;

	DebugPrint("\nLink: http://afstage.legacy.com/$strNewspaper/\n");

	#---------------
	# Links by Date
	#---------------
	$intFound         = FALSE;
	$intRecordCounter = 0;
	DebugPrint("\n\n");
	DebugPrint("LINKS BY DATE:\n\n");
	DebugPrint(sprintf('%-20s', "Start Date")  . sprintf('%-20s', "Stop Date") . sprintf('%-10s', "Direct Links") . "\n" );
	DebugPrint(sprintf('%-20s', "-----------")  . sprintf('%-20s', "---------") . sprintf('%-10s', "-----------------") . "\n" );
	foreach  (sort keys %dateRangeLinks) {
		DebugPrint($_ . " (" . $dateRangeLinks{$_} . ")\n");
		$intRecordCounter += $dateRangeLinks{$_};
		$intFound = TRUE;
	}
	if (!$intFound) {
		DebugPrint(sprintf('%-20s', "None")  . sprintf('%-20s', "None") . sprintf('%-10s', "0") . "\n" );
	}
	DebugPrint(sprintf('%-20s', "-----------")  . sprintf('%-20s', "---------") . sprintf('%-10s', "---------") . "\n" );
	DebugPrint(sprintf('%-20s', "Total")  . sprintf('%-20s', "") . sprintf('%-10s', $intRecordCounter) . "\n" );


	#------------------------------------------
	# Display stats for these batch of feeds.
	#------------------------------------------
	$intFound         = FALSE;
	$intRecordCounter = 0;
	my $strNoOfProcessedFeeds = keys %intAdInFeedCntrHash;
	DebugPrint("\n\n");
	DebugPrint("NOTICE BREAKDOWN BY FEED:\n\n");
	DebugPrint(sprintf('%-60s', "Processed Feeds in Batch") . sprintf('%-20s',"Upload Time") . sprintf('%-20s', "Ads in Feed") . "\n");
	DebugPrint(sprintf('%-60s', "------------------------") . sprintf('%-20s', "----------------") . sprintf('%-20s', "--------------") . "\n");
	foreach  (sort keys %intAdInFeedCntrHash) {
		DebugPrint($_ . sprintf('%-20s', $intAdInFeedCntrHash{$_}) . "\n");
		$intRecordCounter += $intAdInFeedCntrHash{$_};
		$intFound = TRUE;
	}
	$intGrandTotalAds = $intRecordCounter;
	if (!$intFound) {
		DebugPrint(sprintf('%-60s', "None") . sprintf('%-20s', "") . sprintf('%-20s', "0") . "\n");
	}
	DebugPrint(sprintf('%-60s', "------------------------") . sprintf('%-20s', "----------------") . sprintf('%-20s', "-----------") . "\n");
	DebugPrint(sprintf('%-60s', "Total") . sprintf('%-20s', "") . sprintf('%-20s', $intRecordCounter) . "\n");


	$intFound         = FALSE;
	$intSpacing       = -20;
	$intRecordCounter = 0;
	DebugPrint("\n\n");
	DebugPrint("NOTICE BREAKDOWN BY DATE:\n\n");
	DebugPrint(sprintf('%-40s',"Newspaper") . sprintf('%'.$intSpacing.'s', "Start Date")  . sprintf('%-20s', "Stop Date") . sprintf('%-10s', "Count") . "\n" );
	DebugPrint(sprintf('%-40s',"------------------") . sprintf('%'.$intSpacing.'s', "-----------")  . sprintf('%-20s', "---------") . sprintf('%-10s', "---------") . "\n" );
	foreach  (sort keys %dateRangeCount) {
		DebugPrint(sprintf('%'.$intSpacing.'s', $_) .  sprintf('%'.$intSpacing.'s', $dateRangeCount{$_}) . "\n");
		$intRecordCounter += $dateRangeCount{$_};
		$intFound = TRUE;
	}
	if (!$intFound) {
		DebugPrint(sprintf('%-40s',"None") . sprintf('%'.$intSpacing.'s', "None")  . sprintf('%-20s', "None") . sprintf('%-10s', "0") . "\n" );
	}
	DebugPrint(sprintf('%-40s',"------------------") . sprintf('%'.$intSpacing.'s', "-----------")  . sprintf('%-20s', "---------") . sprintf('%-10s', "---------") . "\n" );
	DebugPrint(sprintf('%'.$intSpacing.'s', "Total")  . sprintf('%-40s',"") . sprintf('%-20s', "") . sprintf('%-10s', $intRecordCounter) . "\n" );

	$intFound         = FALSE;
	$intRecordCounter = 0;
	DebugPrint("\n\n");
	DebugPrint("NOTICE BREAKDOWN BY TYPE:\n\n");
	DebugPrint(sprintf('%-40s',"Newspaper") . sprintf('%-40s',"Notice Type") . sprintf('%-30s',"Legacy Payment Code") . sprintf('%-10s',"Count") ."\n");
	DebugPrint(sprintf('%-40s',"------------------") . sprintf('%-40s',"------------------") . sprintf('%-30s',"----------------------------") . sprintf('%-20s',"--------") ."\n");
	foreach  (sort keys %intNoticeTypeCntr) {
		DebugPrint( $_ . sprintf('%-20s',$intNoticeTypeCntr{$_})."\n");
		$intRecordCounter += $intNoticeTypeCntr{$_};
		$intFound = TRUE;
	}
	if (!$intFound) {
		DebugPrint(sprintf('%-40s',"None") . sprintf('%-40s',"None") . sprintf('%-30s',"None") . sprintf('%-20s',"0") ."\n");
	}
	DebugPrint(sprintf('%-40s',"------------------") . sprintf('%-40s',"------------------") . sprintf('%-30s',"----------------------------") . sprintf('%-20s',"--------") ."\n");
	DebugPrint(sprintf('%-40s',"Total") . sprintf('%-40s',"") . sprintf('%-30s',"") . sprintf('%-20s',$intRecordCounter) ."\n");

	$intFound         = FALSE;
	$intRecordCounter = 0;
	DebugPrint("\n\n");
	DebugPrint("FOUND IMAGES:\n\n");
	DebugPrint(sprintf('%-70s',"Source ID+LastName") . sprintf('%-8s',"Type") . sprintf('%-8s',"Index") . sprintf('%-40s',"Found Images") ."\n");
	DebugPrint(sprintf('%-70s',"------------------------------------") . sprintf('%-8s',"-----") . sprintf('%-8s',"----") . sprintf('%-40s',"----------------------------") ."\n");
	foreach (sort keys %found_images) {
		DebugPrint( $_ . sprintf('%-40s', $found_images{$_}) . "\n");
		$intFound = TRUE;
		$intRecordCounter++;
	}
	if (!$intFound) {
		DebugPrint(sprintf('%-70s',"None") . sprintf('%-8s',"None") . sprintf('%-8s',"None") . sprintf('%-40s',"None") ."\n");
	}
	DebugPrint(sprintf('%-70s',"------------------------------------") . sprintf('%-8s',"-----") . sprintf('%-8s',"----") . sprintf('%-40s',"----------------------------") ."\n");
	DebugPrint(sprintf('%-70s',"Total") . sprintf('%-8s',"") . sprintf('%-8s',"") . sprintf('%-40s',$intRecordCounter) ."\n");

	$intFound         = FALSE;
	$intRecordCounter = 0;
	DebugPrint("\n\n");
	DebugPrint("MISSING/BROKEN IMAGES:\n\n");
	DebugPrint(sprintf('%-70s',"Source ID+LastName") . sprintf('%-8s',"Type") . sprintf('%-8s',"Index") . sprintf('%-40s',"Missing or 0 byte Images") ."\n");
	DebugPrint(sprintf('%-70s',"------------------------------------") . sprintf('%-8s',"-----") . sprintf('%-8s',"----") . sprintf('%-40s',"----------------------------") ."\n");
	foreach (sort keys %missing_images) {
		DebugPrint( $_ . sprintf('%-40s', $missing_images{$_}) . "\n");
		$intFound = TRUE;
		$intRecordCounter++;
	}
	if (!$intFound) {
		DebugPrint(sprintf('%-70s',"None") . sprintf('%-8s',"None") . sprintf('%-8s',"None") . sprintf('%-40s',"None") ."\n");
	}
	DebugPrint(sprintf('%-70s',"------------------------------------") . sprintf('%-8s',"-----") . sprintf('%-8s',"----") . sprintf('%-40s',"----------------------------") ."\n");
	DebugPrint(sprintf('%-70s',"Total") . sprintf('%-8s',"") . sprintf('%-8s',"") . sprintf('%-40s',$intRecordCounter) ."\n");

	$intFound         = FALSE;
	$intRecordCounter = 0;
	DebugPrint("\n\n");
	DebugPrint("UNMAPPED ICONS:\n\n");
	DebugPrint(sprintf('%-70s',"Source ID+LastName") . sprintf('%-8s',"Type") . sprintf('%-8s',"Index") . sprintf('%-40s',"Unmapped Icon References") ."\n");
	DebugPrint(sprintf('%-70s',"------------------------------------") . sprintf('%-8s',"-----") . sprintf('%-8s',"----") . sprintf('%-40s',"----------------------------") ."\n");
	foreach (sort keys %unmapped_icons) {
		DebugPrint( $_ . sprintf('%-40s', $unmapped_icons{$_}) . "\n");
		$intFound = TRUE;
		$intRecordCounter++;
	}
	if (!$intFound) {
		DebugPrint(sprintf('%-70s',"None") . sprintf('%-8s',"None") . sprintf('%-8s',"None") . sprintf('%-40s',"None") ."\n");
	}
	DebugPrint(sprintf('%-70s',"------------------------------------") . sprintf('%-8s',"-----") . sprintf('%-8s',"----") . sprintf('%-40s',"----------------------------") ."\n");
	DebugPrint(sprintf('%-70s',"Total") . sprintf('%-8s',"") . sprintf('%-8s',"") . sprintf('%-40s',$intRecordCounter) ."\n");

	DebugPrint("\n\n");
	DebugPrint("MALFORMED NAMES (Note: Only checks for blanks and weird characters)\n\n");
	DebugPrint(sprintf('%-60s',"Feed File") . sprintf('%-40s',"Bad Names Source ID") . sprintf('%-30s',"First Name")  . sprintf('%-30s',"Last Name") ."\n");
	DebugPrint(sprintf('%-60s',"--------------------") . sprintf('%-40s',"------------------") . sprintf('%-30s',"-------------------------")  . sprintf('%-30s',"-------------------------") ."\n");
	foreach my $thisName (sort keys %badNames) {
		DebugPrint( $thisName . "\n");
	}
	$intRecordCounter = keys %badNames;
	my $intPercentErrorRate = 0.00;
	if ($intGrandTotalAds) {
		$intPercentErrorRate = $intRecordCounter/$intGrandTotalAds * 100;
	}
	DebugPrint("\n");
	DebugPrint(sprintf('%-30s',"Total ads processed").      " = " . $intGrandTotalAds ."\n");
	DebugPrint(sprintf('%-30s',"Total ads with bad names"). " = " . $intRecordCounter ."\n");
	DebugPrint(sprintf('%-30s',"Percent Error Rate") .      " = " .  sprintf('%0.2f',$intPercentErrorRate) . " \% \n");


	$intFound         = FALSE;
	$intRecordCounter = 0;
	DebugPrint("\n\n");
	DebugPrint("EXTRACTED EMAILS AND VALIDATION:\n\n");
	DebugPrint(sprintf('%-60s',"Feed File")  . sprintf('%-25s',"Source ID")  . sprintf('%-60s',"Extracted Email") . sprintf('%-10s',"Valid") ."\n");
	DebugPrint(sprintf('%-60s',"------------------------------") . sprintf('%-25s',"----------")  . sprintf('%-60s',"----------------------------------------") . sprintf('%-10s',"---------") ."\n");
	foreach (sort keys %intValidatedEmailCntr) {
		my $strValid = "Yes";
		if (!$intValidatedEmailCntr{$_}) { $strValid = "No";	}
		DebugPrint($_ . sprintf('%-10s',$strValid) . "\n");
		$intFound = TRUE;
		$intRecordCounter++;
	}
	if (!$intFound) {
		DebugPrint(sprintf('%-60s',"None")  . sprintf('%-25s',"None")  . sprintf('%-60s',"None") . sprintf('%-10s',"None") ."\n");
	}
	DebugPrint(sprintf('%-60s',"------------------------------") . sprintf('%-25s',"----------")  . sprintf('%-60s',"----------------------------------------") . sprintf('%-10s',"---------") ."\n");
	DebugPrint(sprintf('%-60s',"Total") . sprintf('%-25s',"")  . sprintf('%-60s',"") . sprintf('%-10s',$intRecordCounter) ."\n");

	$intRecordCounter = 0;
	DebugPrint("\n\n");
	DebugPrint("VALID SPOTLIGHT PHOTOS:\n\n");
	DebugPrint(sprintf('%-40s',"Newspaper") . sprintf('%-60s',"Source ID+LastName") . sprintf('%-40s',"Main Photo") . sprintf('%-7s',"Width") . sprintf('%-7s',"Height") ."\n");
	DebugPrint(sprintf('%-40s',"------------------------------") . sprintf('%-60s',"------------------------------------") . sprintf('%-40s',"--------------") . sprintf('%-7s',"-----") . sprintf('%-7s',"-----") ."\n");
	foreach (sort keys %MainPhotoHash) {
		DebugPrint( $_ . "\n");
		$intRecordCounter++;
	}
	if (not (keys %MainPhotoHash)) {
		DebugPrint(sprintf('%-40s',"None") . sprintf('%-60s',"None") . sprintf('%-40s',"None") . sprintf('%-7s',"None") . sprintf('%-7s',"None") ."\n");
	}
	DebugPrint(sprintf('%-40s',"------------------------------") . sprintf('%-60s',"------------------------------------") . sprintf('%-40s',"--------------") . sprintf('%-7s',"-----") . sprintf('%-7s',"-----") ."\n");
	DebugPrint(sprintf('%-40s',"") . sprintf('%-60s',"Total") . sprintf('%-40s',$intRecordCounter) . sprintf('%-7s',"") . sprintf('%-7s',"") ."\n");


	if (keys %strWeirdChars) {
		DebugPrint("\n\n");
		DebugPrint("WEIRD CHARACTERS:\n\n");
		DebugPrint(sprintf('%-60s',"Feed File") . sprintf('%-20s',"Word")  . sprintf('%-5s',"Count") . "\n");
		DebugPrint(sprintf('%-60s',"----------------------------------------") . sprintf('%-20s',"---------------")  . sprintf('%-5s',"-----") . "\n");
		foreach (sort keys %strWeirdChars) {
			DebugPrint( $_ . $strWeirdChars{$_} . "\n");
		}
		DebugPrint("\n");
	}

	if (keys %intAdIdCntr) {
		$intFound = FALSE;
		DebugPrint("\n\n");
		DebugPrint("REUSED SOURCE IDS:\n\n");
		DebugPrint(sprintf('%-40s',$strNewspaper) . sprintf('%-40s',"Reused AdId") . sprintf('%-10s',"Count") ."\n");
		DebugPrint(sprintf('%-40s',"--------------------") .sprintf('%-40s',"------------------") . sprintf('%-10s',"----------") ."\n");
		foreach my $id (sort keys %intAdIdCntr) {
			$id = "Not Found" unless ($id);
			if ($intAdIdCntr{$id} < 2) {next}
			DebugPrint( $id . sprintf('%-40s', $intAdIdCntr{$id}) . "\n");
			$intFound = TRUE;
		}
		if (!$intFound) {
			DebugPrint(sprintf('%-40s',"None") . sprintf('%-40s',"None") . sprintf('%-10s',"None") ."\n");
		} else { DebugPrint("\n"); }
	}

	my @dates = sort keys %dateStamps;
	my $start = shift @dates || "";
	my $end   = pop @dates || $start;
	my $strNoticeLink = "http://afstage.legacy.com/obituaries/$strNewspaper/obituary-browse.aspx" .
		"?Startdate=$start&Enddate=$end&entriesperpage=25";
	DebugPrint("$strNoticeLink");
	
	DebugPrint("\n\nNAMES:\n\n");
	foreach my $name (sort keys %names) {
		DebugPrint(sprintf('%-' . $max_name_length . 's',$name) . " $names{$name}\n");
	}

}# end sub obtReport


