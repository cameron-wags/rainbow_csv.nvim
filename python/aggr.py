#!/usr/bin/env python

import sys
import os
import argparse
import random


#class RBParsingError(Exception):
#    pass


class Marker:
    def __init__(self, marker_id, value):
        self.marker_id = marker_id
        self.value = value

    def __str__(self):
        raise TypeError('Marker')


class MinAggregator:
    def __init__(self):
        self.stats = dict()

    def increment(self, key, val):
        cur_aggr = self.stats.get(key)
        if cur_aggr is None:
            self.stats[key] = val
        else:
            self.stats[key] = min(cur_aggr, val)

    def get_final(self, key):
        return self.stats[key]


class MaxAggregator:
    def __init__(self):
        self.stats = dict()

    def increment(self, key, val):
        cur_aggr = self.stats.get(key)
        if cur_aggr is None:
            self.stats[key] = val
        else:
            self.stats[key] = max(cur_aggr, val)

    def get_final(self, key):
        return self.stats[key]


class SubkeyChecker:
    def __init__(self):
        self.subkeys = dict()

    def increment(self, key, subkey):
        old_subkey = self.subkeys.get(key)
        if old_subkey is None:
            self.subkeys[key] = subkey
        elif old_subkey != subkey:
            raise RuntimeError('Unable to group by "{}", different values in output: "{}" and "{}"'.format(key, old_subkey, subkey))

    def get_final(self, key):
        return self.subkeys[key]



aggr_init_stage = True
initialization_counter = 0
functional_aggregators = list()


def init_aggregator(generator_name, val):
    global initialization_counter
    assert initialization_counter == len(functional_aggregators)
    functional_aggregators.append(generator_name())
    res = Marker(initialization_counter, val)
    initialization_counter += 1
    return res


def MIN(val):
    return init_aggregator(MinAggregator, val) if aggr_init_stage else val


def MAX(val):
    return init_aggregator(MaxAggregator, val) if aggr_init_stage else val


def main():
    #parser = argparse.ArgumentParser()
    #parser.add_argument('--verbose', action='store_true', help='Run in verbose mode')
    #parser.add_argument('--num_iter', type=int, help='number of iterations option')
    #parser.add_argument('file_name', help='example of positional argument')
    #args = parser.parse_args()
    #
    #num_iter = args.num_iter
    #file_name = args.file_name

    global aggr_init_stage
    global initialization_counter

    all_keys = set()
    nfields = 0
    aggregators = []
    for line in sys.stdin:
        line = line.rstrip('\n')
        fields = line.split('\t')
        nfields = max(nfields, len(fields))

        key = fields[1]
        all_keys.add(key)
        transparent_values = [key, MIN(fields[3]), MAX(fields[3]), 'hello', MAX(fields[7])]
        if aggr_init_stage:
            for i, trans_value in enumerate(transparent_values):
                if isinstance(trans_value, Marker):
                    aggregators.append(functional_aggregators[trans_value.marker_id])
                    aggregators[-1].increment(key, trans_value.value)
                else:
                    aggregators.append(SubkeyChecker())
                    aggregators[-1].increment(key, trans_value)
            aggr_init_stage = False
        else:
            for i, trans_value in enumerate(transparent_values):
                aggregators[i].increment(key, trans_value)


    for key in all_keys:
        out_vals = [ag.get_final(key) for ag in aggregators]
        out_vals = [str(v) for v in out_vals]
        print '\t'.join(out_vals)

if __name__ == '__main__':
    main()
