import subprocess
import collections
import csv
import math
import numpy as np

# Step 1: Get the list of all files with the number of changes
def get_file_change_counts():
    command = ["git", "log", "--name-only", "--pretty=format:"]  # Get the list of files changed in each commit
    result = subprocess.run(command, capture_output=True, text=True, errors='replace')
    files = result.stdout.strip().splitlines()

    file_change_count = collections.Counter(files)
    return file_change_count

# Step 2: Identify outliers based on standard deviations from the median
def identify_outliers(file_change_counts, num_std_dev=3):
    change_counts = np.array(list(file_change_counts.values()))
    median = np.median(change_counts)
    std_dev = np.std(change_counts)

    outliers = {}
    for file, count in file_change_counts.items():
        if abs(count - median) > num_std_dev * std_dev:
            outliers[file] = count

    return outliers

# Step 3: Write the results to a CSV file showing outlier files
def write_results_to_csv(outliers, output_file="xxxxxxxxxx.csv"):
    with open(output_file, mode='w', newline='') as file:
        writer = csv.writer(file)
        
        # Write the header
        writer.writerow(["File", "Total Changes"])
        
        # Write the outlier files and their total changes
        for file, total_changes in outliers.items():
            writer.writerow([file, total_changes])

# Main function to execute the steps
def main():
    file_change_count = get_file_change_counts()
    
    # Identify outliers based on changes significantly deviating from the median
    outliers = identify_outliers(file_change_count)
    
    # Write the results to a CSV file
    write_results_to_csv(outliers)

if __name__ == "__main__":
    main()
