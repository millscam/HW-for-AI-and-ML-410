# Heilmeier draft
As of right now, I have chosen YOLO as my algorithm to work on since I know this is doable and a "safe option". But as I was looking at algorithms I also found an algorithm for sign-language image processign that I thought was interesting, but there is not as much documentation as YOLO. So I will be looking into both over the next week and ultimately pick one before M1. Heres the githup repo if your curious https://github.com/hthuwal/sign-language-gesture-recognition
## What are you trying to do? Articulate your objectives using absolutely no jargon.

build/design a chiplet that will accelerate the image processing speed of YOLO without the use of GPU CPU or other prebuilt hardware

## How is it done today, and what are the limits of current practice?

usually YOLO algortithms work best with large GPUs, but decent ones are very expensive and power hungry, and CPUs cannot handle demand of this kind of algorithm.

## What is new in your approach and why do you think it will be successful?

The accelerator architecture chiplet will be designed specifically at layers related to tensor ops. It can succeed because those layers are mostly large arrays that can be reshaped or optimized.
