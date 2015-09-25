# Use Microcontroller Chips as Helpers #

I recently bought two I2C IO Expanders to add 8 ports for 8 LEDs and another 8 ports for a DAC to drive an audio speaker.

The lesson here is that now I wished I had just used another microcontroller chip!

The IO Expanders were $1.xx, while an ATMega48P is $2.xx, so virtually the same price!  (One ATMega has enough pins to do what both IO Expander chips are doing).

AND

I could have dumped the libraries for this stuff into the ATMega so that I would no longer have to fuss over it in every program I write.  The second ATMega can do fancy interrupt processing to offload that programming complexity from the main Arduino processor.

So the lesson is:

Don't buy stupid helper chips when a microcontroller chip would also do the job.  Who cares if it's overkill?

The only down side is that the ATMega48P chip is much larger physically than the IO Expander chips.  So you need a little more PC board real estate.