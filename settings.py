# testing .txt
# PATH = r"C:/Users/aguerrevere/Documents/haystack/tests"

# for which.py
PARSER_PATH = r"C:/Projects/PerlScripts/BerkshireParser"

# destination path for which.py
DESTINATION_PATH = r'C:/Users/aguerrevere/Documents/haystack/individual_pattern_tables'

# actual Projects folder
PARSERS_PATH = r"C:/Projects/PerlScripts"


# obtExtractFieldsFromFeed
more_standard_patterns = '''
$xmlTag = "UniqueID";
$strAdId
$xmlTag = "PostDate";
$strDeathNoticeDate
$xmlTag = "EndDate";
$strStopDate
$xmlTag = "NoticeType";
$strNoticeType
$xmlTag = "Email";
$strEmail
$xmlTag = "Email";
$strEmail
$xmlTag = "FuneralHome";
$strFuneralHome
$xmlTag = "FuneralHomeAddress";
$strFuneralHomeAddr
$xmlTag = "FuneralHomeCity";
$strFuneralHomeCity
$xmlTag = "Notice";
$strDeathNotice
$xmlTag = "fullname";
$strDeathNoticeName
$xmlTag = "City";
$strCity
$xmlTag = "State";
$strState
$xmlTag = "DateBorn";
$strYearBorn
$xmlTag = "DateDeceased";
$strYearDeceased
$xmlTag = "Spotlight";
$intShowInSpotlight
$xmlTag = "DateDeceased";
$strDateOfDeath
'''

# print(more_standard_patterns)
# print([i for i in more_standard_patterns.splitlines() if i != ''])
# print(len([i for i in more_standard_patterns.splitlines() if i != '']))
