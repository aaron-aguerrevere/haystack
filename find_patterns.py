###--- IMPORTS ---###
import config


###--- GLOBAL VARIABLES ---###
path = config.TESTS_PATH


###--- FUNCTIONS ---###
def find_patterns():
    # verifies if both lists are the same parsers
    with open(path + '/saltlake/SaltLaketribuneiPublishParser.pl', 'r') as ipub_parser:
        ipub_data = ipub_parser.read()

    with open(path + '/atlanta/AtlantaParser.pl', 'r') as older:
        older_data = older.read()

    patterns = list()

    for element in ipub_data.split(' '):
        if element not in older_data:
            patterns.append(element)

    found_patterns = open("found_patterns.txt", "a+")
    found_patterns.write('\n'.join([str(pattern) for pattern in patterns]))
    found_patterns.close()


###--- DRIVER CODE ---###
if __name__ == "__main__":
    find_patterns()