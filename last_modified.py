###--- IMPORTS ---###
import os
import time
import pathlib
import settings

path_to_file = os.path.dirname(__file__)

# path_to_file = os.path.dirname(settings.PARSERS_PATH)

print("Last modified: %s" % time.ctime(os.path.getctime(path_to_file)))

# checks for last modified of each parser in device
    # for parser in parsers:
    #     print(parser, time.ctime(os.path.getctime(path_to_parsers + "/" + parser)))
    # turns out it gives you datetime stamp of local device which isn't helpful