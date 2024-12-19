# XPalm application on 3 sites


## To do

- [] The stresses from the FTSW are applied in many places, but it could be applied twice because it is already applied to `TEff`. This was the case with the phyllochron were we had phylo_slow that represented the stress effect on the phyllochron, and we also had TEff. We should work on that. We basically have two solutions:
  - We could remove the stress from the TEff and keep it only in the phyllochron and other processes directly. This would be the most logical solution.
  - We could only use the TEff, it would simplify the code of many models, but we can't apply a different stress to the different processes then.