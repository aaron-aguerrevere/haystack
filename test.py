import settings

patterns = settings.more_standard_patterns

test = {
    'name': 'YumaSunAdPerfectParser.pl', 
    '$xmlTag = "UniqueID";': False, 
    '$xmlTag = "PostDate";': False, 
    '$xmlTag = "EndDate";': False, 
    '$xmlTag = "NoticeType";': False, 
    '$xmlTag = "Email";': False, 
    '$xmlTag = "FuneralHome";': False, 
    '$xmlTag = "FuneralHomeAddress";': True, 
    '$xmlTag = "FuneralHomeCity";': True, 
    '$xmlTag = "Notice";': False, 
    '$xmlTag = "fullname";': False, 
    '$xmlTag = "City";': True, 
    '$xmlTag = "State";': False, 
    '$xmlTag = "DateBorn";': False, 
    '$xmlTag = "DateDeceased";': False, 
    '$xmlTag = "Spotlight";': False, 
    '$strAdId': True, 
    '$strStopDate': False, 
    '$strEmail': True, 
    '$strFuneralHome': False, 
    '$strFuneralHomeCity': False, 
    '$strDeathNoticeName': False, 
    '$strState': False, 
    '$strYearDeceased': False, 
    '$strDateOfDeath': False, 
    '$strDeathNoticeDate': True, 
    '$strDeathNotice': True, 
    '$strYearBorn': True, 
    '$strNoticeType': True, 
    '$strCity': True, 
    '$strFuneralHomeAddr': True, 
    '$intShowInSpotlight': True}


for i in test.keys():
    if i not in [i for i in patterns.splitlines() if i != '']:
        print(i)