# Design test firmware for the common pueo-pynq firmware

* basic_design : routes ADC channels 0-3 to buffers 0-3
* biquad8_design : routes ADC channels 0-1 through single biquad8s for testing
* lowpass_design : routes ADC channels 0-3 through the halfband filter, into buffers 0-3 and channels 0-1 to dac outputs 0-1
* agc_design : routes ADC channel 0 through AGC core, outputs AGC output to buffer 0 and DAC (TIMES 16 FOR VISIBILITY)

## Modules that do no ADC/DAC routing, but do have some wrapping with WISHBONE

* biquad_double_design : Takes an 8-fold 12 bit input stream, applies two biquad notches configured via WISHBONE
* agc_design_minimal : Takes an 8-fold 12 bit input stream, applies AGC configured via WISHBONE

# Accessing internal WISHBONE registers

The internal WISHBONE bus is accessible from the serial port routed to EMIO. I think it's almost always /dev/ttyPS1
since /dev/ttyPS0 is the console (maybe not on a standalone SURFv6A but uh whatever).

You need the SerialCOBSDevice Python module from pueo-python, as well as the Python cobs module installed. Then do

```
from serialcobsdevice import SerialCOBSDevice
sdv = SerialCOBSDevice('/dev/ttyPS1', 1000000)
```
and you can do
```
# write 0x12345 to 0x100
sdv.write(0x100, 0x12345)
# read from 0x184
val = sdv.read(0x184)
```

n.b. the pueo-python repository has reorganized recently, serialcobsdevice.py is located under ``pueo/common``.
