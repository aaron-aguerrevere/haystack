###--- FUNCTIONS ---###
def compare():
    # verifies if both lists are the same parsers
    with open('intAllowNameUpdate_hits.txt', 'r') as first:
        data_one = first.read()

    with open('ALLOW_DECEASED_NAME_UPDATE_hits.txt', 'r') as second:
        data_two = second.read()

    for word in data_one.split(' '):
        if word not in data_two:
            print(word)
            break
        else:
            print("They are the same.")
            break


###--- DRIVER CODE ---###
if __main__ == __name__:
    compare()