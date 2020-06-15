Note that these are 0-based numbers. If you ever find official docs, they'll probably be 1-based.

still need to confirm from wfsays.c:
30 (System Outputs)
			/* <><><><> <><><><> <><><EH2><EH1> <><RV><CC2><CC1> */
			/* RV CC CC2 Blower Alarm Accessory Lockout EH1 EH2 ECM 5-spd ECM /*
			/* 80 seems to toggle whenever - heartbeat? */
			/* 40 */
			/* maybe 0x20 is EH2 and 0x10 is EH1 */
			/* 04 seems to be RV 1=cool, 0=heat */
			/* 02 seems to be Hi Compressor CC2 */
			/* 01 seems to be Lo Compressor CC1 */
			/* on stage1 cool 3 bits come on: 200, 008, and 001 */
31 (Status)
			/* 1b9 = on/off/off/on/on/on */
			/* 194 when on and set to EHEAT */
			/* 80 */
			/* 40 */
			/* 20 Dehumid or not - DH */
			/* 10 Fan On - G */
			/* 08 Cool=0 Heat=1 - O */
			/* 04 EHEAT? - W? */
			/* 02 Stage2 - Y2 */
			/* 01 Stage1 -Y1 */
1109 (Heating LL)
1112 (Leaving Air)
1113 (Suction Temp)
1115 (Discharge Pressure)
1116 (Suction Pressure)
1124 (Evap Sat Temp)
1125 (SuperHeat)
1134 (Cond Sat Temp)
1136 (Subcool (F * 10, signed))
1155 (Heat of Extraction)

|Register|Mask|Description|
|2||ABC Program Version (* 100)|
|3||? Program Version (* 100)|
|8||? Unit Type (always 0)|
|16||Line Voltage|
|19||FP1 (F * 10)|
|20||FP2 (F * 10)|
|25||Last Fault Number|
|26||Last Lockout Fault Number (high bit is set if true; mask off to get fault number)|
|30||System Outputs|
||0x40|RV|
||0x20|EH2?|
||0x10|EH1?|
||0x02|CC2|
||0x01|CC1|
|31||Status|
||0x20|DH?|
||0x10|Fan?|
||0x08|Cool/Heat?|
||0x04|EHeat?|
||0x02|Stage 2?|
||0x01|Stage 1?|
|88..91|ABC Program (ASCII, space padded)|
|92..104||Model Number (ASCII, spaced padded)|
|105..109||Serial Number (ASCII)|
|211..218||VS Drive Details (General, Derate, Safemode, Alarm; 32 bits each)|
|280||VS Drive Details (EEV2 Ctl)|
|340||Blower Only Speed|
|341||Lo Compressor ECM Speed|
|342||Hi Compressor ECM Speed|
|346||ECM Clg% (signed)|
|347||Aux Heat ECM Speed|
|567||Entering Air (F * 10)|
|601..699||Fault History (Count of each type of fault that has occurred)|
|601||
|1103||AXB Inputs|
||?|Smart Grid|
||?|HA1|
||?|HA2|
||?|MBA|
||?|S3D|
||?|AR2|
|1104||AXB Outputs|
||0x10|Accessory 2|
||0x02|Loop Pump|
||0x01|DHW|
||?|Div Valve|
||?|Dehum/Reheat|
|1105||Blower Amps (* 10)|
|1106||Aux Amps (* 10)|
|1107||Compressor 1 Amps (* 10)|
|1108||Compressor 2 Amps (* 10)|
|1110||Leaving Water (F * 10)|
|1111||Entering Water (F * 10)|
|1114||DHW Temp (F * 10)|
|1117||Waterflow (gpm * 10)|
|1147|Compressor Watts|
|1149|Blower Watts|
|1151|Aux Watts|
|1153|Total Watts|
|1165|VS Pump Watts|
