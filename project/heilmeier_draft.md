# Heilmeier draft
As of now, I have chosen a Sign Language gesture-recognition algorithm using CNN and RNN. Still, I am a little nervous about the amount of information provided in the GitHub repo. I also looked into YOLO as another algorithm since it is a "safer option" and is also related to image processing. So I will be looking into both over the next week and ultimately pick one before M1. Here's the GitHub repo if you're curious https://github.com/hthuwal/sign-language-gesture-recognition
## What are you trying to do? Articulate your objectives using absolutely no jargon.

Build or design a chiplet accelerator that speeds up the heavy math in that kind of system related to convolution and image processing without the help of a CPU or GPU. 

## How is it done today, and what are the limits of current practice?

usually CNN and RNN algortithms work best with large GPUs, but decent ones are very expensive and power hungry, and standard CPUs struggle to keep up with the demand of CNN and RNN.

## What is new in your approach and why do you think it will be successful?

The new part is a accelerator chiplet aimed at: convolution (and related dense tensor ops) in the per-frame network, and matrix-style operations inside the RNN/LSTM cells over the sequence. Those operations are predictable at the tensor level. 

It can succeed if the design feeds the compute array enough bandwidth/reuse so processing elements stay busy and you measure improvement on a set scale with fixed frame size, sequence length, and a chosen CNN+RNN configuration.
