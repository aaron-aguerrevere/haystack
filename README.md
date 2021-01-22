# Haystack

Python script to search for words in files inside directories.

### The What

We want to inventory and bucket a series of parsers.

### The Goal

To find commonalities among several parsers and categorize some parsers as "standard."

Focus on "more standard fields" within `obtExtractFieldsFromFeed` section in parsers.

### The How
##### (current iteration)

Script should:
- pierce through file tree where Parsers live: path,
- read and search files looking for certain patterns
- identify files where given patterns are found
- create a digestable list of parsers that match.

Currently: 

- `inventory.py` counts directories, files, provides totals & filters newer parsers
- `find_patterns.py` identifies elements that are in ipub and not older parsers
- `search.py` searches all Parsers to see if patterns are found in them
- `verify.py` checks if two parsers within the list of hits are the exact same
- `last_modified.py` checks for "last modified" date of each file in path
- `which.py` reads one specified Perl parsers and checks which "more standard" patterns are contained in it, then creates a `csv` file with the result

### NEXT STEPS

Should we make an API out of this?
