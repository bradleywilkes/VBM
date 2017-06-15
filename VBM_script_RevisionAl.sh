#!/bin/bash
dim=3  # image dimensionality
AP=“/antsbin/bin” # path to ANTs binaries

#variable definitions
warped=_Warped #variable to identify .nii.gz to .nii extension change has occurred correctly 
warpedMnc=_Warped.mnc #variable to tell to use mnc extension
Mnc=.mnc
IntCorr=_IntensityCorrected.nii
WarpedNii=_Warped.nii.gz #extension for moving files into lsq6 folder after registration

############################################################################################################################
#STEP 0 -- Have user specify the Input Directory and create necessary subdirectories
echo -n "Enter Input Directory and press [ENTER]: "
read InputDir 
echo "You selected $InputDir"

#take list of files in input directory and create a text file of that list (for reference later in the script)
ls "$InputDir" > "$InputDir"/InputData.txt

if [ ! -d "$InputDir"/IntensityCorrection ]; then
	mkdir ${InputDir}/IntensityCorrection
fi

if [ ! -d "$InputDir"/LSQ6 ]; then
	mkdir ${InputDir}/LSQ6
fi	

if [ ! -d "$InputDir"/LSQ6/Model ]; then
	mkdir ${InputDir}/LSQ6/Model
fi	

if [ ! -d "$InputDir"/LSQ6/PopulationTemplate ]; then
	mkdir ${InputDir}/LSQ6/PopulationTemplate
fi	

if [ ! -d "$InputDir"/SYN/ ]; then
	mkdir ${InputDir}/SYN/
fi	

if [ ! -d "$InputDir"/SYN/PopulationTemplate ]; then
	mkdir ${InputDir}/SYN/PopulationTemplate
fi	

if [ ! -d "$InputDir"/MVTC ]; then
	mkdir ${InputDir}/MVTC
fi	

if [ ! -d "$InputDir"/MVTC/InitialTemplate ]; then
	mkdir ${InputDir}/MVTC/InitialTemplate
fi	

if [ ! -d "$InputDir"/MVTC/PopulationTemplate ]; then
	mkdir ${InputDir}/MVTC/PopulationTemplate
fi	

echo "ah, ah , ah,  ah , makin a change, makin a change!"

############################################################################################################################
#STEP 1 -- Transform registered NII images to MNC for intensity correction (step 3)

for file in ${InputDir}/*; do
	if [ ${InputDir}/${file%.nii.gz}=FLASH3D ]
		then nii2mnc ${file} ${file%.nii.gz}.mnc #referencing other script "nii2mnc" that does the conversion. 
	fi
done


	#move the MNC files to Intensity Correction 

for file in ${InputDir}/*; do
	if [ ${file##.}=mnc ] 
		then mv ${InputDir}/*${Mnc} ${InputDir}/IntensityCorrection
	fi
done


############################################################################################################################
###STEP 2 -- Intensity correction of MNC files. 

for file in ${InputDir}/IntensityCorrection/*; do
		nu_correct ${file} ${file%.mnc}_IntensityCorrected.mnc	#referencing other script that performs intensity correction.
done

############################################################################################################################
#STEP 3 -- Convert intensity corrected MNC files back to nifti

for file in ${InputDir}/IntensityCorrection/*; do
	
	if [ ${file%.mnc}=_IntensityCorrected ]
		then mnc2nii ${file} ${file%.mnc}.nii #referencing other script "mnc2nii" that does inverse conversion.
	fi
	
	for i in ${InputDir}/IntensityCorrection/*; do
	
		if [ ${file##.}=nii ] 
			then cp ${InputDir}/IntensityCorrection/*${IntCorr} ${InputDir}/LSQ6/Model
		fi
		
	done

done

############################################################################################################################
#STEP 4 -- Rigid registration of all brains from native space to the same stereotactic space as a manually selected "Model.nii.gz"

for file in ${InputDir}/LSQ6/Model/*; do 
		antsRegistrationsyn.sh -d 3 -t r -n 2 -o ${file%.nii}_lsq6_to_Model_ -f ${InputDir}/Model.nii.gz -m ${file}
	    ###ANTS is a series of scripts for neuroimaging analysis. This "antsRegistrationsyn.sh" performs image registration.###
done

##This step needs to keep the LSQ6 registered images in the appropriate folder, but they are also needed 
#as input for initial template creation and population template created. I should probably just leave them where
##they are and reference these files from their location. 
for i in ${InputDir}/LSQ6/Model/*; do
		cp ${InputDir}/LSQ6/Model/*${WarpedNii} ${InputDir}/MVTC/InitialTemplate/
		cp ${InputDir}/LSQ6/Model/*${WarpedNii} ${InputDir}/MVTC/PopulationTemplate/
done

############################################################################################################################
#STEP 5 -- Build initial template for the multivariate template construction (step 6)

cd ${InputDir}/MVTC/InitialTemplate

buildtemplateparallel.sh -d 3 -o Initial_ -c 0 -n 0 -t RA -m 1x0x0 *_Warped.nii.gz
###ANTS is a series of scripts for neuroimaging analysis. This "buildtemplateparallel.sh" generates an averaged template image.###
### This step generates the "initial template", used as the starting point for generating the "full template" ###

############################################################################################################################
#STEP 6 -- Build full template with lsq6_to_Model brains as input and InitialTemplate.nii.gz as the initial template

cd ${InputDir}/MVTC/PopulationTemplate/

buildtemplateparallel.sh -d 3 -o StrainComparison_ -c 2 -i 10 -g 0.10 -n 0 -m 100x70x20 -r 0 -t GR -z ${InputDir}/MVTC/InitialTemplate/Initial_template.nii.gz *_Warped.nii.gz
###ANTS is a series of scripts for neuroimaging analysis. This "buildtemplateparallel.sh" generates an averaged template image.###
### This step generates the "full template", using the "initial template" as a starting target ###

############################################################################################################################
#STEP 7 -- Re-register individual brains to full template


for file in ${InputDir}/IntensityCorrection/*; do
	if [ ${file##.}=nii ] 
		then cp ${InputDir}/IntensityCorrection/*${IntCorr} ${InputDir}/LSQ6/PopulationTemplate
	fi
done

for file in ${InputDir}/LSQ6/PopulationTemplate/*; do 
		antsRegistrationsyn.sh -d 3 -t r -n 2 -o ${file%.nii}_LSQ6_to_PopulationTemplate_ -f ${InputDir}/MVTC/PopulationTemplate/StrainComparison_template.nii.gz -m ${file}
		###ANTS is a series of scripts for neuroimaging analysis. This "antsRegistrationsyn.sh" performs image registration.###
		### This step does linear (6 parameter) registration of each brain from native space to the template space##
done

############################################################################################################################
#STEP 8 -- Use linearly re-registered (lsq6) brains and do full non-linear registration to the population average template

#leave these files where they are???
for i in ${InputDir}/MVTC/PopulationTemplate/*; do
	if [ ${file##.}=nii ] 
		then cp ${InputDir}/MVTC/PopulationTemplate/*${WarpedNii} ${InputDir}/SYN/PopulationTemplate
	fi
done

for file in ${InputDir}/SYN/PopulationTemplate/*; do 
		antsRegistrationsyn.sh -d 3 -t s -n 2 -o ${file%.nii.gz}_SYN_to_PopulationTemplate_ -f ${InputDir}/MVTC/PopulationTemplate/StrainComparison_template.nii.gz -m ${file}
		###ANTS is a series of scripts for neuroimaging analysis. This "antsRegistrationsyn.sh" performs image registration.###
		### This step takes linearly registered (aligned) brains and performs non-linear registration of these brains to the "full template". 
done