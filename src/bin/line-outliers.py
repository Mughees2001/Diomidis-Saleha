import pandas as pd
import numpy as np

def load_csv(filename):
    return pd.read_csv(filename)

def save_csv(df, filename):
    df.to_csv(filename, index=False)

def remove_duplicates(df):
    unique_df = df.drop_duplicates()
    save_csv(unique_df, 'unique_rows.csv')
    return unique_df

def filter_highest_mod_count(df):
    result_df = df.loc[df.groupby('Line Number')['Modification Count'].idxmax()]
    save_csv(result_df, 'highest_counts.csv')
    return result_df

def detect_outliers_and_save(df):
    values = df['Modification Count'].values
    mean = np.mean(values)
    std_dev = np.std(values)
    z_scores = (values - mean) / std_dev
    outliers = df[np.abs(z_scores) > 3]
    save_csv(outliers, 'outlier_lines.csv')
    return outliers

def process_csv(filename):
    df = load_csv(filename)
    
    unique_df = remove_duplicates(df)
    
    highest_mod_count_df = filter_highest_mod_count(unique_df)
    
    outliers_df = detect_outliers_and_save(highest_mod_count_df)
    
    print("Outliers based on z-scores:")
    print(outliers_df)

if __name__ == '__main__':
    process_csv('line_modifications.csv')
