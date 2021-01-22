# Haystack

Python script to search for "patterns" in files inside directories.

### The What

We want to inventory and bucket a series of parsers.

### The Goal

To find commonalities among several parsers and categorize some parsers as "_more standard_."

Focus on "more standard fields" within `obtExtractFieldsFromFeed` section in Perl parsers: there are 34 such patterns (see settings.py)

### The How
##### (current iteration)

Script:
- pierces through file tree where Parsers live, _recursively_: path,
- reads and searches files looking for certain patterns
- identifies files where given patterns are found
- create a digestable csv of parsers that match, as well as a csv for each parser within certain filter paramenter providing which pattern is contained in it

Main (yet to be refactored): 

- `0_inventory.py` counts directories, files, provides totals & filters newer parsers that follow specif "more recent" naming conventions
- `1_search.py` searches all Parsers to see if patterns are found in them

Auxiliary (used for proof of concept, later integrated into "Main"):

- `verify.py` checks if two parsers within the list of hits are the exact same
- `last_modified.py` checks for "last modified" date of each file in path
- `which.py` reads one specified Perl parsers and checks which "more standard" patterns are contained in it, then creates a `csv` file with the result

### NEXT STEPS

Should we make an API out of this?
