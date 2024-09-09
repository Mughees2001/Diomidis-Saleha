import pandas as pd
from scipy import stats
import numpy as np

# Load the CSV file
def load_csv(filename):
    return pd.read_csv(filename)

# Save DataFrame to a CSV file
def save_csv(df, filename):
    df.to_csv(filename, index=False)

# Remove duplicate rows and save
def remove_duplicates(df):
    unique_df = df.drop_duplicates()
    save_csv(unique_df, 'unique_rows.csv')
    return unique_df

# Keep rows with the highest modification count per line number
def filter_highest_mod_count(df):
    result_df = df.loc[df.groupby('Line Number')['Modification Count'].idxmax()]
    save_csv(result_df, 'highest_counts.csv')
    return result_df

# Calculate z-scores and filter outliers, then save them
def detect_outliers_and_save(df):
    values = df['Modification Count'].values
    z_scores = stats.zscore(values)
    outliers = df[np.abs(z_scores) > 3]
    save_csv(outliers, 'outlier_lines.csv')
    return outliers

# Main function to process the data
def process_csv(filename):
    # Step 1: Load the CSV
    df = load_csv(filename)
    
    # Step 2: Remove duplicates
    unique_df = remove_duplicates(df)
    
    # Step 3: Filter to only the highest modification counts
    highest_mod_count_df = filter_highest_mod_count(unique_df)
    
    # Step 4: Detect outliers based on z-scores and save them
    outliers_df = detect_outliers_and_save(highest_mod_count_df)
    
    # Print or handle outliers
    print("Outliers based on z-scores:")
    print(outliers_df)

if __name__ == '__main__':
    # Specify the CSV file name
    process_csv('input.csv')
