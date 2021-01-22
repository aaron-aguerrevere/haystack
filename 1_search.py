###--- IMPORTS ---###
import os
import settings
import csv


###--- GLOBAL VARIABLES ---###
path_to_parsers = settings.PARSERS_PATH

contains = list() # if search is small, else could take too much memory

more_standard_parsers_list = list()

more_standard_patterns_list = [i for i in settings.more_standard_patterns.splitlines() if i != '']

# directory_dictionary = dict()



###--- FUNCTIONS ---###
def import_more_standard_parsers_csv():
    '''
     imports "more standar parsers" csv and creates 
     and updates global variable "more_standard_parsers_list
     used in `search_folder()` to filter the search of patterns
     to only withint those "more standard" parsers
    '''

    global more_standard_parsers_list

    with open('more_standard_parsers_list.csv', 'r') as more_standard_parsers:
        reader = csv.reader(more_standard_parsers)
        more_standard_parsers_list = [row[0] for row in list(reader)]

    return more_standard_parsers_list



def change_directory():
    '''
     changes directory once search is performed
     thus piercing thru entire file tree
    '''

    path = settings.PARSERS_PATH

    search_folder_for_all_standard_patterns(path)



def search_folder_for_all_standard_patterns(path):
    '''
     performs search and appends hits to "contains"
    '''
    global contains, more_standard_parsers_list, more_standard_patterns_list, directory_dictionary

    directories = os.listdir(path)

    for directory in directories:
        if directory.endswith(".pl"):
            if directory in more_standard_parsers_list:
                try:
                    perl_file = open(path + "/" + directory, "r")
                    perl_file_reader = perl_file.read()
                    if all(p in perl_file_reader for p in more_standard_patterns_list):
                        hits = open(f"parsers_containing_the_{len(more_standard_patterns_list)}_fields_from_obtExtractFieldsFromFeed.csv", "a+")
                        hits.write("%s\n" % directory)
                        hits.close()
                except:
                    pass

        elif "." not in directory.split(" "):
            # 15 exeptions
            if directory != "vssver2.scc" and\
            not(directory.endswith('.txt')) and\
            not(directory.endswith('.pl.obsolete')) and\
            not(directory.endswith('.cmd')) and\
            not(directory.endswith('.xml')) and\
            not(directory.endswith('.inc')) and\
            not(directory.endswith('.TXT')) and\
            not(directory.endswith('.pl.old')) and\
            not(directory.endswith('.htm')) and\
            not(directory.endswith('.template')) and\
            not(directory.endswith('.config')) and\
            not(directory.endswith('.config-DEPRECATED')) and\
            not(directory.endswith('.jpg')) and\
            not(directory.endswith('.doc')) and\
            not(directory.endswith('.bat')) and\
            not(directory.endswith('.exe')):
                search_folder_for_all_standard_patterns(path + "/" + directory)



###--- DRIVER CODE ---###
if __name__ == "__main__":
    import_more_standard_parsers_csv()
    change_directory()