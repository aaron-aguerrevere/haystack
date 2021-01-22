###--- IMPORTS ---###
import settings
import csv


###--- GLOBAL VARIABLES ---###
more_standard_patterns_list = [i for i in settings.more_standard_patterns.splitlines() if i != '']


###--- FUNCTIONS ---###

def create_csv_which_parsers_contain_which_patterns():
    with open('TEST_parser.pl', 'r', encoding="utf8") as parser:
        reader = parser.read()

    with open('which.csv', 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=['pattern', 'found'])
        writer.writeheader()

        for pattern in more_standard_patterns_list:
            writer.writerows([{'pattern': pattern, 'found': pattern in reader}])

    # print(f"\n\n  {count} out of {len(more_standard_patterns_list)} patters found in this parser")


###--- DRIVER CODE ---###
if __name__ == "__main__":
    create_csv_which_parsers_contain_which_patterns()