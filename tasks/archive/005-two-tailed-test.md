Header:
005-two-tailed test
Status: Done
Created: 2026-11-22
Updated 2026-11-22
Due: 2026-11-22

**Goal**
Utilize a two-tailed statistical test on two to four bands with chemical relevance to determine if defective coffee bean sample means significantly differ from defective free coffee bean sample means, for both processing stages

**Progress Log**
2026-11-22: I decided to do a first analysis of the data using a two-tailed test, as per Lucas' suggestion, with a select few bands.

I thought about focusing on the O-H bands, since I noticed that the green coffee had the largest visual difference in SNV absorbance between the O-H bands of the defect-free and defect spectra. However, when I checked the initial characterization file, it showed the moisture content and water activity of the defect-free beans and each defect, and I did not see any significant difference in the moisture content between the two. The difference in the O-H bands must be due to something else unrelated to the defects. This should be addressed later, after the first working draft.

I then looked up other typical, diagnostic peaks for coffee. I settled on caffeine, which has a C=O stretch at ~ 1700 - 1635 cm^-1, and chlorogenic acids, which have a specific marker at ~ 1600 and ~ 1515 cm^-1. I also found that lipids have -CH2- stretches at ~ 2922 (asymmetric) and ~ 2853 (symmetric) cm^-1, but the main focus will be on caffeine and chlorogenic acids as the potential indicator between defect and defect-free coffee beans, since a separate study used them as indicators. (https://pmc.ncbi.nlm.nih.gov/articles/PMC7500798/)

For the two-tailed test, I will narrow down the caffeine peak to between 1659 - 1654 cm^-1, based on these two sources that have studied caffeine content in coffee using FTIR: 
https://link.springer.com/article/10.1007/s002160050063
https://publisher.unimas.my/ojs/index.php/TUR/article/download/1137/681

For chlorogenic acids, I will use the 1725, 1687, 1640, 1289, and 1114 cm^-1 peaks. These are considered strong and very strong peaks of the experimental wavenumbers for chlorogenic acid (5-CQA) from this source: https://pmc.ncbi.nlm.nih.gov/articles/PMC5855685/

The asssitant was prompted to create the code to run the test with those peaks. 

**Outcome**
Done 2026-11-22
The result was a first-look analysis using a two-tailed test with the preprocessed data. For the green coffee, 5/6 of the bands differed significantly, and only one of the chlorogenic acid peaks reporting as not having a significant difference. For the roasted coffee, 5/6 of the bands differed significantly, and the caffeine peak reported as not having a significant difference. As of now, it appears that ATR-FTIR can distinguish between defective and defect-free coffee beans at both processing stages, but I need to do additional research on how defects actually change the chemical composition of coffee beans, as well as refine band windows and candidates. 