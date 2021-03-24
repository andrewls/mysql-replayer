import matplotlib
import matplotlib.pyplot as plt
import json as json
import dateutil.parser
import sys
import os
import numpy

if len(sys.argv) < 3:
    print("Usage: python3 process_metrics.py <FILE_NAME> <BIN_SIZE_IN_SECONDS>")
    sys.exit()

print("Opening file %s" % sys.argv[1])
TOTAL_LINES = int(os.popen('cat %s | wc -l' % sys.argv[1]).read())
print("File is %d lines in total" % TOTAL_LINES)
BIN_SIZE = int(sys.argv[2])
print("Bin size is %d seconds" % BIN_SIZE)

metrics = {}

def update_average_metric(metrics, metric_name, bin, metric_bin_name):
    metric = metrics[metric_name]
    metric_bin = bin.get(metric_bin_name, {})
    existing_average = metric_bin.get('average', 1)
    existing_weight = metric_bin.get('weight', 0)
    if metric_name == ':operation' or metric_name == 'first_word':
        totals = metric_bin.get('totals', { })
        total_for_type = totals.get(metric, 0)
        total_for_type = total_for_type + 1
        totals[metric] = total_for_type
        metric_bin['totals'] = totals
    else:
        new_average = numpy.average([existing_average, metric], weights=[existing_weight, 1])
        metric_bin['average'] = new_average
        metric_bin['weight'] = existing_weight + 1

        # Add this data point for p95 and p99 calculations
        data = metric_bin.get('data_points', [])
        data.append(metric)
        metric_bin['data_points'] = data

    # And now we can just go ahead and write all the changes out.
    bin[metric_bin_name] = metric_bin

def process_bin(bin_index, dict):
    bin = dict.get(bin_index, None)
    print("Checking if we should process bin %r" % bin_index)
    if bin and not bin['processed']:
        print("Processing bin %r" % bin_index)
        # aggregate all the data points for each metric
        print("Keys I'm processing: %r" % bin.keys())
        for metric in bin.keys():
            if metric == 'processed' or metric == 'operation' or metric == 'action' or metric == 'tps':
                continue
            print("\tProcessing metric %s" % metric)
            data = bin[metric]['data_points']
            # And now we need to compute 95th and 99th percentile
            p95, p99 = numpy.percentile(data, [95, 99])
            bin[metric]['p95'] = p95
            bin[metric]['p99'] = p99
            del bin[metric]['data_points']
        bin['processed'] = True
        bin['tps'] = bin['tps'] / BIN_SIZE

current_maximum_bin = 0

with open(sys.argv[1]) as f:
    line = f.readline()
    lines = 0
    while line:
        lines += 1
        if lines % 10_000 == 0:
            print("Processing line %d of %d" % (lines, TOTAL_LINES))
        metric = json.loads(line)

        # First order of business is to go ahead and determine what bin this
        # sucker falls into
        timestamp = metric[':entry_timestamp']['^t']
        bin_start = (timestamp // BIN_SIZE) * BIN_SIZE

        # And now we can collect each metric we care about.
        bin = metrics.get(bin_start, { 'processed': False, 'tps': 0 })
        update_average_metric(metric, ':query_queue_latency', bin, 'queue_latency')
        update_average_metric(metric, ':execution_time', bin, 'execution_time')
        update_average_metric(metric, ':operation', bin, 'operation')
        metric['first_word'] = metric[':query'].split()[0]
        update_average_metric(metric, 'first_word', bin, 'action')
        metrics[bin_start] = bin

        # Now calculate when this query was started and add it to the
        # corresponding bin for QPS calculations. Start time is equal to
        # start timestamp plus queue latency.
        metric['start_time'] = timestamp + metric[':query_queue_latency']
        start_time_bin_start = metric['start_time'] // BIN_SIZE * BIN_SIZE
        # And now that we have the bin, we add it to the TPS for that bin
        start_time_bin = metrics.get(start_time_bin_start, { 'processed': False, 'tps': 0 })
        start_time_bin['tps'] += 1
        metrics[start_time_bin_start] = start_time_bin

        # Finally, whenever the bin changes to a higher bin than it previously
        # has, that means that a full bin has passed. In the case of almost
        # all bin sizes, that's going to mean that all of the queries have
        # finished executing from the bin before the previous bin, which means
        # that we can now compute the p95 and p99 statistics for those bins.
        if bin_start > current_maximum_bin:
            process_bin(current_maximum_bin - BIN_SIZE, metrics)
            current_maximum_bin = bin_start
        line = f.readline()

    # the last bin will always need to be processed, and possibly the one before it
    # as well
    process_bin(current_maximum_bin - BIN_SIZE, metrics)
    process_bin(current_maximum_bin, metrics)

    print("Total lines: %d" % lines)
    print("Metric totals: \n%r" % metrics)
