/*
 * ============================================================
 * OJAS - Arduino Environmental Parameter Emitter (10 s Demo)
 * ============================================================
 *
 * HARDWARE:
 *   Arduino Uno
 *
 * ROLE:
 *   The Arduino acts as the environmental-data front end for
 *   the STM32. There is NO ultrasonic sensor in this version.
 *
 * DATA SENT TO STM32:
 *   - depth_m
 *   - temperature_C
 *   - salinity_PSU
 *   - turbidity_NTU
 *   - c_ref_mps  -> reference Mackenzie value for validation ONLY
 *
 * IMPORTANT:
 *   The STM32 must NOT use c_ref_mps for waveform selection.
 *   It should calculate Mackenzie sound speed itself from the
 *   transmitted environmental parameters, then perform the
 *   Sensor/Mackenzie LUT lookup.
 *
 * The 24 profiles below are representative rows taken from the
 * supplied ocean_data.csv. Each profile was selected because it
 * uniquely matches one of W01-W24 using the supplied sensor LUT.
 *
 * PROFILE ID is only a test-profile identifier. It is NOT the
 * selected Wxx waveform. The STM32 performs the actual Wxx
 * selection.
 *
 * UART packet example:
 *   OJAS,PROFILE=17,DEPTH_M=5.000,TEMP_C=22.5956,
 *   SAL_PSU=36.28175,TURB_NTU=0.35250,CREF_MPS=1529.85718
 *
 * ============================================================
 */

#include <Arduino.h>
#include <avr/pgmspace.h>

/* ============================================================
 * USER SETTINGS
 * ============================================================
 */

/* Default profile to transmit. 1..24 */
const uint8_t START_PROFILE = 17;

/*
 * true  -> automatically cycle through all 24 profiles
 * false -> continuously transmit START_PROFILE
 */
const bool AUTO_CYCLE = false;

/* Time between transmitted packets: 10 seconds for demo */
const unsigned long TX_PERIOD_MS = 10000UL;

/* UART speed */
const unsigned long BAUD_RATE = 115200UL;


/* ============================================================
 * ENVIRONMENTAL PROFILE STRUCTURE
 * ============================================================
 */

struct OceanProfile
{
    uint8_t id;
    float depth_m;
    float temperature_C;
    float salinity_PSU;
    float turbidity_NTU;
    float c_ref_mps;
};


/* ============================================================
 * VALIDATED PROFILES
 * ============================================================
 *
 * Values are stored in program memory so SRAM usage stays low.
 */

const OceanProfile profiles[24] PROGMEM =
{
    {  1, 400.0f,    7.487f,       34.93815f, 0.62245f, 1486.92761f },
    {  2, 1250.0f,   4.66515f,      34.94745f, 0.62320f, 1489.80977f },
    {  3, 500.0f,    8.45945f,      35.00845f, 0.28450f, 1492.34710f },
    {  4, 500.0f,    9.75766625f,   34.7269108f,0.72760f,1496.78033f },
    {  5, 2500.0f,   1.95829766f,   34.72000f, 0.72760f, 1499.15437f },
    {  6, 200.0f,   12.7185367f,    35.213547f, 0.72760f, 1502.78435f },
    {  7, 10.0f,    15.1558053f,    35.0447563f,0.72760f,1507.39959f },
    {  8, 200.0f,   14.64545f,      35.89825f, 1.37740f, 1509.90193f },
    {  9, 1.0f,     19.1079f,       30.08805f, 1.81055f, 1513.37138f },
    { 10, 1.0f,     22.31615f,      22.70335f, 0.15805f, 1513.98888f },
    { 11, 50.0f,    17.7298f,       35.92570f, 0.39205f, 1516.89534f },
    { 12, 50.0f,    19.03625f,      36.30960f, 0.92885f, 1521.08727f },
    { 13, 100.0f,   19.2366f,       36.41005f, 0.60045f, 1522.58097f },
    { 14, 1.0f,     21.56545f,      33.08280f, 1.35470f, 1523.55176f },
    { 15, 1.0f,     24.14555f,      29.11700f, 1.77185f, 1525.82046f },
    { 16, 10.0f,    21.7509f,       36.44220f, 0.66680f, 1527.94204f },
    { 17, 5.0f,     22.5956f,       36.28175f, 0.35250f, 1529.85718f },
    { 18, 10.0f,    23.32545f,      36.35285f, 0.32620f, 1531.85451f },
    { 19, 5.0f,     24.2121f,       35.55565f, 0.99620f, 1533.08211f },
    { 20, 5.0f,     24.52935f,      35.79075f, 1.17060f, 1534.10675f },
    { 21, 30.0f,    24.8306f,       36.27470f, 0.43115f, 1535.76231f },
    { 22, 20.0f,    28.1372f,       33.16805f, 0.90590f, 1539.83400f },
    { 23, 10.0f,    28.7249f,       33.97140f, 0.79440f, 1541.78593f },
    { 24, 30.0f,    29.22655f,      36.08665f, 0.77440f, 1545.37922f }
};


/* ============================================================
 * RUNTIME STATE
 * ============================================================
 */

uint8_t activeProfile = START_PROFILE;
unsigned long lastTransmit = 0;
unsigned long sequence = 0;


/* ============================================================
 * FUNCTION DECLARATIONS
 * ============================================================
 */

bool loadProfile(uint8_t id, OceanProfile &out);
void sendProfile(const OceanProfile &p);
void sendReadyMessage();
void sendHeartbeat();


/* ============================================================
 * SETUP
 * ============================================================
 */

void setup()
{
    Serial.begin(BAUD_RATE);

    delay(500);

    sendReadyMessage();

    activeProfile = constrain(START_PROFILE, 1, 24);

    lastTransmit = millis() - TX_PERIOD_MS;
}


/* ============================================================
 * MAIN LOOP
 * ============================================================
 */

void loop()
{
    unsigned long now = millis();

    if ((now - lastTransmit) >= TX_PERIOD_MS)
    {
        lastTransmit = now;

        OceanProfile p;

        if (loadProfile(activeProfile, p))
        {
            sequence++;
            sendProfile(p);
        }

        if (AUTO_CYCLE)
        {
            activeProfile++;

            if (activeProfile > 24)
            {
                activeProfile = 1;
            }
        }
    }
}


/* ============================================================
 * LOAD PROFILE FROM PROGMEM
 * ============================================================
 */

bool loadProfile(uint8_t id, OceanProfile &out)
{
    if (id < 1 || id > 24)
    {
        return false;
    }

    memcpy_P(
        &out,
        &profiles[id - 1],
        sizeof(OceanProfile)
    );

    return true;
}


/* ============================================================
 * SEND ENVIRONMENTAL PACKET
 * ============================================================
 */

void sendProfile(const OceanProfile &p)
{
    Serial.print("OJAS,PROFILE=");
    Serial.print(p.id);

    Serial.print(",SEQ=");
    Serial.print(sequence);

    Serial.print(",DEPTH_M=");
    Serial.print(p.depth_m, 4);

    Serial.print(",TEMP_C=");
    Serial.print(p.temperature_C, 5);

    Serial.print(",SAL_PSU=");
    Serial.print(p.salinity_PSU, 5);

    Serial.print(",TURB_NTU=");
    Serial.print(p.turbidity_NTU, 5);

    /*
     * Reference only.
     * STM32 should calculate its own Mackenzie result.
     */
    Serial.print(",CREF_MPS=");
    Serial.print(p.c_ref_mps, 5);

    Serial.println();
}


/* ============================================================
 * STARTUP MESSAGE
 * ============================================================
 */

void sendReadyMessage()
{
    Serial.println("OJAS,ARDUINO,READY");
    Serial.println("OJAS,MODE=ENVIRONMENTAL_PROFILE_EMITTER");
    Serial.println("OJAS,PARAMS=DEPTH,TEMP,SALINITY,TURBIDITY,CREF");
    Serial.print("OJAS,START_PROFILE=");
    Serial.println(START_PROFILE);
    Serial.print("OJAS,AUTO_CYCLE=");
    Serial.println(AUTO_CYCLE ? "1" : "0");
}


/* ============================================================
 * UNUSED HEARTBEAT HELPER
 * ============================================================
 */

void sendHeartbeat()
{
    Serial.println("OJAS,HEARTBEAT");
}
