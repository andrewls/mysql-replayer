import matplotlib
import matplotlib.pyplot as plt
import json as json
import dateutil.parser
import sys
import os
import numpy
import datetime

def graph_metric(domain, data, y_label, title, filename):
    fig, ax = plt.subplots()
    if len(data) == 3:
        avg, p95, p99 = data
        plt.plot(domain, avg, label='Average')
        plt.plot(domain, p95, label='P95')
        plt.plot(domain, p99, label='P99')
        ax.legend()
    else:
        plt.plot(domain, data)
    ax.xaxis.set_major_locator(plt.MaxNLocator(16))
    ax.set(xlabel='Hours into peak', ylabel=y_label, title=title)
    plt.grid()
    # plt.xticks(rotation=90)
    ax.set_ylim(ymin=0)
    fig.tight_layout()
    fig.savefig(filename)
    plt.clf()

FILENAME_PREFIX = sys.argv[2]

def get_stats(results, timestamps, label):
    avg = [results[bin][label]['average'] for bin in timestamps]
    p95 = [results[bin][label]['p95'] for bin in timestamps]
    p99 = [results[bin][label]['p99'] for bin in timestamps]
    return (avg, p95, p99)

# read the dictionary into memory
with open(sys.argv[1]) as f:
    results = eval(f.read())

    # First order of business is to grab and sort the keys we'll be using for
    # everything else.
    epoch_timestamps = sorted(results.keys())

    # aurora has some insane data points for TPS
    # and I think it's because we have an absolutely nuts pre-process
    # So I'm going to eliminate all the pre-peak data points for aurora
    # mysql's first data point appears to be a weird one too
    peak_timestamps = [t for t in epoch_timestamps if results[t]['tps'] > 0 and results[t]['tps'] < 100000]


    # Now go ahead and grab the data we care about for each graph.
    # First, TPS
    tps = [results[bin]['tps'] for bin in peak_timestamps]

    first_timestamp = peak_timestamps[0]
    hours_into_peak = [(t - first_timestamp) / 3600 for t in peak_timestamps]

    graph_metric(hours_into_peak, tps, 'TPS', 'Transactions Per Second Over Time', '%s-tps.png' % FILENAME_PREFIX)

    # And now queue latency
    avg_queue_latency, p95_queue_latency, p99_queue_latency = get_stats(results, peak_timestamps, 'queue_latency')
    graph_metric(hours_into_peak, (avg_queue_latency, p95_queue_latency, p99_queue_latency), 'Latency (seconds)', 'Time Spent Waiting To Execute', '%s-queue-latency.png' % FILENAME_PREFIX)

    # Execution time
    avg_execution_time, p95_execution_time, p99_execution_time = get_stats(results, peak_timestamps, 'execution_time')
    graph_metric(hours_into_peak, (avg_execution_time, p95_execution_time, p99_execution_time), 'Execution Time (seconds)', 'Execution Time', '%s-execution-time.png' % FILENAME_PREFIX) 
