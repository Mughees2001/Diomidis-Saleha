import subprocess
import collections
import csv
import numpy as np

def get_file_change_counts():
    command = ["git", "log", "--name-only", "--pretty=format:"]  # Get the list of files changed in each commit
    result = subprocess.run(command, capture_output=True, text=True, errors='replace')
    files = result.stdout.strip().splitlines()

    file_change_count = collections.Counter(files)
    return file_change_count

def identify_outliers(file_change_counts, num_std_dev=3):
    change_counts = np.array(list(file_change_counts.values()))
    median = np.median(change_counts)
    std_dev = np.std(change_counts)

    outliers = {}
    for file, count in file_change_counts.items():
        if abs(count - median) > num_std_dev * std_dev:
            outliers[file] = count

    return outliers

def write_results_to_csv(outliers, output_file="xxxxxxxxxx.csv"):
    with open(output_file, mode='w', newline='') as file:
        writer = csv.writer(file)
        
        writer.writerow(["File", "Total Changes"])
        
        for file, total_changes in outliers.items():
            writer.writerow([file, total_changes])

def main():
    file_change_count = get_file_change_counts()
    
    outliers = identify_outliers(file_change_count)
    
    write_results_to_csv(outliers)

if __name__ == "__main__":
    main()
