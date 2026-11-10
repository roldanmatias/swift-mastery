// expect: overlapping accesses to 'nights'
func f() { var nights = [1, 2]; swap(&nights[0], &nights[1]) }
