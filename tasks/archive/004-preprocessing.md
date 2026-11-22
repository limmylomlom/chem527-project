Header: 004-preprocessing
Status: Done
Created: 2026-11-21
Updated: 2026-11-22
Due: 2026-11-22

**Goal**
Cleaning up the spectra generated from the raw data file in code before performing any analysis. 

**Progress Log**
2026-11-12: Asked the assistant what steps to take to preprocess the data. The assistant responded with a code that identified chemically relevant regions (650 - 1800 cm^-1, 2800 - 3700 cm^-1) and incorporated an SNV and Savitzky-Golay first derivative calculation (derivative was not used to plot the data) within the code and plotted a 10-spectra plot that used every 10 single rows from the raw data. Initially, the plot connected the ends of the chemically relevant regions with a straight line, so I asked the assistant to instead trim that region completely and leave it blank.

2026-11-21: I researched preprocessing strategies for FTIR ATR analysis and asked the assistant if, given the preprocessing steps I found, it would make any changes to the existing code upon my request to preprocess the data again with those specific steps. The assistant provided an assessment of the usefulness of each step, which I verified. I asked the assistant to create a new code to preprocess the raw data with just SNV (standard number variant), with the same trimmings as before, but instead of a 10-spectra plot, I asked for a plot with defect & defect-free spectra for green coffee beans and roasted coffee beans separately. I also asked the assistant to create an untrimmed version of the 10-spectra plot for reference to visually verify the trimming of the 1800 - 2800 cm^-1 region. 

2026-11-22: I later realized that the 10-spectra plot did not provide any useful information toward my research question, so I decided to delete the cells that generate those plots, and instead asked the assistant to create new code that would plot an untrimmed version of the defect & defect-free spectra to justify the trimming decision, as well as the decision to not use a derivative.

**Outcome**
Done 2026-11-22
The result was preprocessed raw data via SNV that also justified decisions to trim band-free regions and not use a derivative for preprocessing, and finally plotted the trimmed and preprocessed data as defect and defect-free spectra for each processing stage. 