# Project proposal: 

Austen Lim, CHEM 527, 2026-11-08

Question: Can ATR-FTIR spectra distinguish between defective and defect-free coffee lots, and does that capability persist for roasted coffee?

Data source: Collazos-Escobar, G. A. et al., *Mid-infrared spectral dataset and
machine learning tools for defect detection in green and roasted coffee*,
Version 5, Mendeley Data (2026), https://doi.org/10.17632/dtd2fggpyp.5,
accessed 2026-11-05. License CC BY 4.0.

Data evaluation: 
There are 50 independent coffee lots for two processing stages (green / roasted), which totals to 100 sample-stage spectral observations. 

In the raw data, each row is a separate observation. 

For the columns, V1 indicates defective (1) or defect-free (0) coffee, and is labeled as such in the 'defect-status' column; process indicates either green (0) or roasted (1), and is labeled as such in in the 'processing stage' column; defect category specifies the defect type (bitten, vinegar, drill bit, discolored, black) for each defective coffee; within category ID is a local sequential identifier for each defect type, and the 'README' insists it should not be used as the biological grouping variable; coffee lot ID pairs observations from the same biological sample between processing stages; lastly, the remaining columns cover the spectral range of 648.556784 - 3999.4335 cm^-1, spaced apart by about 3.727 cm^-1, and the values are measured in units of absorbance. 


Limitations:
Five lots per defect type may not be sufficient enough data to create strong, confident conclusions regarding the ability of ATR-FTIR to distinguish between specific defects. It would be best to narrow the scope of this project to defect vs defect-free before and after roasting. 

All coffee lots are arabica from one Colombian department, so the results of this project are limited to this specific lot in this region, and should not be interpreted for other species or origins of coffee. 


If the data do not answer the question:

If comparison between defect and defect-free coffee yield no clear difference, I will report the smallest absorbance difference that would've detected a defect from the data. I would also narrow the analysis further to compare defect-free lots with specific defect types, but with a heavy note that there are only 5 lots for each defect type to compare to. 
