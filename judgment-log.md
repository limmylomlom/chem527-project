# Judgment log: <Austen Lim>

## How I used AI in this project

(Final submission only.)

## Entries

### Nov 21: not using the Savitzky-Golay derivative

- **What the assistant suggested:** 
The assistant suggested to take the Savitzky-Golay derivative on the full spectrum, followed by SNV, for preprocessing.
- **What I did:** accepted, changed, rejected or verified it.
I changed the suggestion.
- **Why, from my data:** 
In the untrimmed SNV plot, I checked that the band-free regions (4000 - 3700 cm^-1 and 2800 - 1800 cm^-1) showed that the spectra overlapped at about -1 SNV with little offset or tilt. I also noticed that there was a small gap in the green coffee bean plot in the 2800 - 1800 cm^-1 region at about 0.05 SNV units, however, it was in a region I chose to exclude and the analysis computes SNV without it, so it was not treated as a reason for a derivative. Given this, I decided to exclude the use of a derivative for its baseline role, and only used SNV for preprocessing.


### Nov 22: moisture content and the 1650 cm^-1 band

- **What the assistant suggested:**
The assistant suggested to consider that the caffeine range (1659 - 1654 cm^-1) overlaps with protein amide I at ~ 1650 cm^-1 and water bending at ~ 1640 cm^-1, noting that the defective green spectra shows a weaker O-H band near 3300 cm^-1, concluding that any differences at ~ 1650 cm^-1 might be due to water instead of caffeine.
- **What I did:**
I changed part of the suggestion
- **Why, from my data:**
I checked the dataset's characterization file for the moisture content for defect-free and defective beans. I found that mean moisture content (%wet basis) for all of the defect types for both green and roasted beans overlapped with the range of the moisture content for defect-free beans of the respective processing stages (10.84 +- 0.32 for green, 2.09 +- 0.32 for roasted). With this, I concluded that it would be highly unlikely that a difference near 1650 cm^-1 should not be attributed to water, and that the weaker O-H band near 3300 cm^-1 for my defective green spectra could be attributed to something else other than water. 
