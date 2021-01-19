###--- IMPORTS ---###
import settings
import os
import csv
import re
import json
import time
import collections


###--- GLOBARL VARIABLES ---###

path_to_parsers = settings.PARSERS_PATH
more_standard_parsers_list = list()

###--- FUNCTIONS ---###

def count_dirs_and_files():
    '''
     Counts directories and files, path and nested, outputs totals.
    '''
    global path_to_parsers

    # parsers = os.listdir(path_to_parsers)
    # print('Number of directories in path:', len(parsers)) # first-level 597

    number_of_directories = 0
    number_of_files = 0

    for base, dirs, files in os.walk(path_to_parsers):
        for d in dirs:
            number_of_directories += 1
        for f in files:
            number_of_files += 1
    
    print('Number of directories, including nested dirs:', number_of_directories)
    print('Number of files:', number_of_files)
    print('More standard parsers (include "Wave2", "iPublish", "AdPerfect" or "AdPay" in file name):')



def tally_in_csv():
    # [!] for current directory
    # for root, directories, files in os.walk("."):
    #     for filename in files:
    #         print(filename)

    global path_to_parsers

    # first-level directories: does not include files inside
    # [!] ALPHABETICAL
    parsers = os.listdir(path_to_parsers)

    with open("perl_parsers_inventory.csv", "w") as f:
        for i, parser in enumerate(parsers):
            if i == 0:
                f.write("%s\n" % parser)
            else:
                f.write("%s\n" % re.sub('Parser', '', parser))
    pass



def create_json(path_to_parsers):
    '''
     Creates a Json with Tree file structure: includes nested directories and files.
    '''
    global more_standard_parsers_list

    d = {'name': os.path.basename(path_to_parsers)}

    if os.path.isdir(path_to_parsers):
        d['type'] = 'directory'
        d['children'] = [create_json(os.path.join(path_to_parsers, x)) for x in os.listdir(path_to_parsers)]
    else:
        d['type'] = 'file'

    # catch newer parsers
    if d['name'].endswith('.pl') and\
     ('Wave2' in d['name'] or\
      'iPublish' in d['name'] or\
       'AdPerfect' in d['name'] or\
        'AdPay' in d['name']):
        more_standard_parsers_list.append(d['name'])
        print(d['name'])

    return d



def print_json():
    '''
     Prints Json created by `create_json` in CLI.
    '''
    
    parsers_json = json.dumps(create_json(path_to_parsers), indent=4)

    print("\n\nAs a json for API purposes: \n")
    # entire json
    print(parsers_json)
    pass



def jackpot():
    '''
     consumes list of newer parsers, 
     which include "Wave2", "iPublish", "AdPerfect" or "AdPay" in file name
     and creates a CSV file with them 
    '''
    global more_standard_parsers_list
    
    with open('more_standard_parsers_list.csv', 'w') as npcsv:
        for parser in more_standard_parsers_list:
            npcsv.write("%s\n" % parser)

    pass



###--- DRIVER CODE ---###
if __name__ == "__main__":
    count_dirs_and_files()
    create_json(path_to_parsers)
    # print_json()
    # tally_in_csv()
    # jackpot()