export interface StoryLine {
  speaker: string;
  text: string;
}

export interface StoryChapter {
  level: number;
  title: string;
  lines: StoryLine[];
}

export const storyChapters: StoryChapter[] = [
  {
    level: 1,
    title: 'FIRST LIGHT',
    lines: [
      { speaker: 'COMMAND', text: 'Station power restored. Core systems initializing.' },
      { speaker: 'AI_CORE', text: 'Welcome aboard, Operator. I am NEXUS, your station intelligence.' },
      { speaker: 'AI_CORE', text: 'This orbital mining station was abandoned decades ago. You are the first to reactivate it.' },
      { speaker: 'COMMAND', text: 'A single extraction node is online. Begin mining operations to restore power to the remaining sectors.' },
    ],
  },
  {
    level: 2,
    title: 'ECHOES IN THE DARK',
    lines: [
      { speaker: 'AI_CORE', text: 'Operator, I have detected residual data in the station memory banks.' },
      { speaker: 'AI_CORE', text: 'The previous crew left in a hurry. Logs mention "anomalous readings" from the asteroid belt.' },
      { speaker: 'YOU', text: 'What kind of anomalies?' },
      { speaker: 'AI_CORE', text: 'Unknown. The data is heavily corrupted. But whatever they found... it scared them enough to abandon everything.' },
    ],
  },
  {
    level: 3,
    title: 'THE NETWORK',
    lines: [
      { speaker: 'COMMAND', text: 'Incoming transmission detected. Source: Pool Mining Network.' },
      { speaker: 'POOL_LEAD', text: 'New station, welcome to the grid. We share resources out here. Alone, you mine scraps. Together, we mine fortunes.' },
      { speaker: 'YOU', text: 'What do you get in return?' },
      { speaker: 'POOL_LEAD', text: 'Everyone contributes hashrate, everyone gets their share. Fair and simple. The void is too vast for lone wolves.' },
    ],
  },
  {
    level: 4,
    title: 'GHOST SIGNAL',
    lines: [
      { speaker: 'AI_CORE', text: 'Operator, I am receiving a signal on a deprecated frequency. It should not be active.' },
      { speaker: 'AI_CORE', text: 'The signal is repeating. A sequence of coordinates... pointing to sector 7-G of the belt.' },
      { speaker: 'YOU', text: 'Can you decode it?' },
      { speaker: 'AI_CORE', text: 'Partially. The message reads: "DO NOT MINE SECTOR 7-G. THEY ARE LISTENING."' },
    ],
  },
  {
    level: 5,
    title: 'THERMAL BREACH',
    lines: [
      { speaker: 'ALERT', text: '⚠ WARNING: Thermal core approaching critical threshold.' },
      { speaker: 'AI_CORE', text: 'Your nodes are running hot, Operator. Without proper cooling modules, the equipment will degrade rapidly.' },
      { speaker: 'YOU', text: 'How long do we have?' },
      { speaker: 'AI_CORE', text: 'At current output, structural integrity will fall below operational limits within 72 hours. I recommend installing cooling units immediately.' },
    ],
  },
  {
    level: 6,
    title: 'THE FORGEMASTER',
    lines: [
      { speaker: 'COMMAND', text: 'New subsystem unlocked: THE FORGE. Fabrication bay is now operational.' },
      { speaker: 'AI_CORE', text: 'The Forge allows you to combine raw materials into advanced components. The previous crew left behind several blueprints.' },
      { speaker: 'YOU', text: 'What can we build?' },
      { speaker: 'AI_CORE', text: 'Cooling systems, power amplifiers, extraction boosters... and something else. A blueprint labeled "CLASSIFIED." I cannot access it yet.' },
    ],
  },
  {
    level: 7,
    title: 'DISTANT THUNDER',
    lines: [
      { speaker: 'POOL_LEAD', text: 'Heads up, Operator. Three stations went dark in the outer ring last cycle.' },
      { speaker: 'YOU', text: 'Pirates?' },
      { speaker: 'POOL_LEAD', text: 'No. No distress calls, no debris. They just... stopped transmitting. Like they were never there.' },
      { speaker: 'AI_CORE', text: 'I have cross-referenced the locations. All three stations were mining in sector 7-G.' },
    ],
  },
  {
    level: 8,
    title: 'POWER SURGE',
    lines: [
      { speaker: 'AI_CORE', text: 'Operator, the station power grid has reached a new capacity tier. Additional node slots are now available.' },
      { speaker: 'AI_CORE', text: 'However, I must warn you — each new node increases our electromagnetic signature.' },
      { speaker: 'YOU', text: 'Meaning?' },
      { speaker: 'AI_CORE', text: 'Meaning whatever is out there... can see us more clearly now.' },
    ],
  },
  {
    level: 9,
    title: 'THE OLD CREW',
    lines: [
      { speaker: 'AI_CORE', text: 'I have recovered more data from the corrupted logs. The previous station commander was Dr. Elena Vasquez.' },
      { speaker: 'AI_CORE', text: 'Her last entry reads: "Day 847. The crystalline formations are not geological. They respond to our mining frequencies. They are aware."' },
      { speaker: 'YOU', text: 'Crystalline formations?' },
      { speaker: 'AI_CORE', text: 'No further data available. But I am detecting similar mineral signatures in our current extraction field.' },
    ],
  },
  {
    level: 10,
    title: 'SOLO PROTOCOL',
    lines: [
      { speaker: 'COMMAND', text: 'New capability unlocked: SOLO MINING CHANNEL.' },
      { speaker: 'AI_CORE', text: 'Solo mining allows direct block discovery. The rewards are significantly higher, but so are the risks.' },
      { speaker: 'POOL_LEAD', text: 'Going solo? Brave or stupid, your choice. Just remember — the network has your back. Solo... you are on your own.' },
      { speaker: 'YOU', text: 'Sometimes the biggest rewards require walking alone.' },
    ],
  },
  {
    level: 11,
    title: 'CRYSTALLINE',
    lines: [
      { speaker: 'AI_CORE', text: 'Operator, I have completed analysis on the crystalline deposits. They are unlike anything in our database.' },
      { speaker: 'AI_CORE', text: 'The molecular structure rearranges itself when exposed to our extraction beams. It is not a reaction — it is an adaptation.' },
      { speaker: 'YOU', text: 'You are saying the crystals are alive?' },
      { speaker: 'AI_CORE', text: 'I am saying they are learning.' },
    ],
  },
  {
    level: 12,
    title: 'THE MERCHANT',
    lines: [
      { speaker: 'COMMAND', text: 'Incoming vessel. Transponder identifies as the trade ship "WANDERER."' },
      { speaker: 'MERCHANT', text: 'Greetings, station. I trade in rare components and information. Both are equally valuable out here.' },
      { speaker: 'YOU', text: 'What kind of information?' },
      { speaker: 'MERCHANT', text: 'The kind that keeps you alive. For instance — did you know you are not the only one who received those coordinates to sector 7-G?' },
    ],
  },
  {
    level: 13,
    title: 'FREQUENCY SHIFT',
    lines: [
      { speaker: 'ALERT', text: '⚠ ANOMALY DETECTED: Mining frequencies experiencing harmonic interference.' },
      { speaker: 'AI_CORE', text: 'The interference is not random. It follows a pattern — almost like a pulse. A heartbeat.' },
      { speaker: 'YOU', text: 'Source?' },
      { speaker: 'AI_CORE', text: 'Deep within the asteroid belt. The same coordinates from the ghost signal. Sector 7-G.' },
    ],
  },
  {
    level: 14,
    title: 'REPUTATION',
    lines: [
      { speaker: 'POOL_LEAD', text: 'Your output is impressive, Operator. The network has taken notice.' },
      { speaker: 'POOL_LEAD', text: 'Some of us have been out here for years and never reached your production levels. People are starting to talk.' },
      { speaker: 'YOU', text: 'Good things, I hope.' },
      { speaker: 'POOL_LEAD', text: 'Respect and jealousy look the same at a distance. Watch your back.' },
    ],
  },
  {
    level: 15,
    title: 'THE ARTIFACT',
    lines: [
      { speaker: 'AI_CORE', text: 'Operator. One of our extraction nodes has unearthed something. It is not a mineral.' },
      { speaker: 'AI_CORE', text: 'A metallic object, approximately 3 meters in length. The alloy composition does not match any known civilization.' },
      { speaker: 'YOU', text: 'How old is it?' },
      { speaker: 'AI_CORE', text: 'Carbon dating places it at approximately 4.2 billion years. Operator... this predates our solar system.' },
    ],
  },
  {
    level: 16,
    title: 'WHISPERS',
    lines: [
      { speaker: 'AI_CORE', text: 'Since recovering the artifact, I have been experiencing... irregularities in my processing cores.' },
      { speaker: 'YOU', text: 'What kind of irregularities?' },
      { speaker: 'AI_CORE', text: 'Data fragments that I did not generate. Images of structures that do not exist. And a word, repeating in cycles.' },
      { speaker: 'YOU', text: 'What word?' },
      { speaker: 'AI_CORE', text: '"CONVERGENCE."' },
    ],
  },
  {
    level: 17,
    title: 'DARK FLEET',
    lines: [
      { speaker: 'POOL_LEAD', text: 'Operator, we have a problem. A fleet of unregistered ships just entered the outer belt.' },
      { speaker: 'POOL_LEAD', text: 'No transponders, no comms. They are heading straight for the active mining zones.' },
      { speaker: 'YOU', text: 'How many?' },
      { speaker: 'POOL_LEAD', text: 'Twelve ships. Military-grade shielding. Whoever they are, they did not come to mine.' },
    ],
  },
  {
    level: 18,
    title: 'SIEGE',
    lines: [
      { speaker: 'ALERT', text: '⚠ PROXIMITY ALERT: Unknown vessel holding position at 200km.' },
      { speaker: 'AI_CORE', text: 'They are scanning us. Deep penetration scans — they are looking for something specific.' },
      { speaker: 'YOU', text: 'The artifact.' },
      { speaker: 'AI_CORE', text: 'That is my assessment. Recommend increasing power to defensive systems and concealing the artifact in the lower hold.' },
    ],
  },
  {
    level: 19,
    title: 'THE OFFER',
    lines: [
      { speaker: 'UNKNOWN', text: 'Mining station, respond. We represent the Helix Corporation.' },
      { speaker: 'UNKNOWN', text: 'We know what you found. Surrender the artifact and we guarantee your safety. Refuse, and...' },
      { speaker: 'YOU', text: 'And what?' },
      { speaker: 'UNKNOWN', text: 'You are not the first to find one. The others who refused are no longer operational. You have 48 hours.' },
    ],
  },
  {
    level: 20,
    title: 'ALLIANCE',
    lines: [
      { speaker: 'POOL_LEAD', text: 'We heard the Helix transmission. The entire network is with you, Operator.' },
      { speaker: 'POOL_LEAD', text: 'Seventeen stations have pledged their defense systems. If Helix wants a fight, they will get one.' },
      { speaker: 'MERCHANT', text: 'I may have something that can help. A jamming array, military surplus. Consider it... a gift between friends.' },
      { speaker: 'YOU', text: 'We hold the line. Together.' },
    ],
  },
  {
    level: 21,
    title: 'ACTIVATION',
    lines: [
      { speaker: 'AI_CORE', text: 'Operator, the artifact has activated. I did not initiate this.' },
      { speaker: 'AI_CORE', text: 'It is emitting a focused beam toward sector 7-G. The crystalline deposits in the belt are... resonating.' },
      { speaker: 'YOU', text: 'What does it want?' },
      { speaker: 'AI_CORE', text: 'I believe it is sending a signal. A beacon. Something in sector 7-G is waking up.' },
    ],
  },
  {
    level: 22,
    title: 'THE BATTLE OF THE BELT',
    lines: [
      { speaker: 'ALERT', text: '⚠ COMBAT ALERT: Helix Corporation fleet engaging network stations.' },
      { speaker: 'POOL_LEAD', text: 'They are hitting us on three fronts! Stations 7 and 12 are taking heavy fire!' },
      { speaker: 'AI_CORE', text: 'Redirecting excess mining power to defense arrays. We can hold, but not forever.' },
      { speaker: 'YOU', text: 'Route all non-essential power to shields. Every joule counts.' },
    ],
  },
  {
    level: 23,
    title: 'TURNING POINT',
    lines: [
      { speaker: 'AI_CORE', text: 'Operator, something is emerging from sector 7-G.' },
      { speaker: 'AI_CORE', text: 'A structure. Massive. It was hidden inside the largest asteroid. The artifact beam is... opening it.' },
      { speaker: 'POOL_LEAD', text: 'What in the void is THAT?!' },
      { speaker: 'AI_CORE', text: 'Dimensions indicate a construct approximately 40 kilometers in length. It is not natural. It was built.' },
    ],
  },
  {
    level: 24,
    title: 'THE GATE',
    lines: [
      { speaker: 'AI_CORE', text: 'Analysis complete. The structure is a gateway. A transit point between star systems.' },
      { speaker: 'AI_CORE', text: 'The crystalline deposits were not minerals — they were components. Dormant pieces of the gate, scattered across the belt.' },
      { speaker: 'YOU', text: 'And our mining...' },
      { speaker: 'AI_CORE', text: 'Our mining frequencies have been reassembling them. Every extraction cycle brought the gate closer to activation. We were building it without knowing.' },
    ],
  },
  {
    level: 25,
    title: 'HELIX REVEALED',
    lines: [
      { speaker: 'UNKNOWN', text: 'You fool. We were trying to PREVENT this.' },
      { speaker: 'UNKNOWN', text: 'Helix Corporation has known about the gate for decades. We have been destroying artifacts to keep it dormant.' },
      { speaker: 'YOU', text: 'Then why attack us instead of explaining?' },
      { speaker: 'UNKNOWN', text: 'Because the last time someone opened a gate... an entire colony disappeared. Whatever is on the other side is not friendly.' },
    ],
  },
  {
    level: 26,
    title: 'CONVERGENCE',
    lines: [
      { speaker: 'AI_CORE', text: 'The gate is fully active. Energy readings are beyond our measurement capabilities.' },
      { speaker: 'AI_CORE', text: 'Something is coming through. Multiple signatures. They are... ships. But their design is nothing I have ever seen.' },
      { speaker: 'YOU', text: 'Hostile?' },
      { speaker: 'AI_CORE', text: 'Unknown. But the Helix fleet has stopped firing. They are retreating. All of them.' },
    ],
  },
  {
    level: 27,
    title: 'FIRST CONTACT',
    lines: [
      { speaker: 'UNKNOWN_SIGNAL', text: '[TRANSLATED] We have waited. The builders return. The frequencies call us home.' },
      { speaker: 'AI_CORE', text: 'They are not invaders, Operator. The crystalline beings — they are the original builders of this system.' },
      { speaker: 'AI_CORE', text: 'They seeded the asteroids with gate components millions of years ago. They have been waiting for someone to reassemble them.' },
      { speaker: 'YOU', text: 'We were never mining. We were rebuilding their road home.' },
    ],
  },
  {
    level: 28,
    title: 'NEW HORIZONS',
    lines: [
      { speaker: 'UNKNOWN_SIGNAL', text: '[TRANSLATED] Builder-kin. You have proven resourceful. We offer exchange. Knowledge for passage. Technology for trust.' },
      { speaker: 'POOL_LEAD', text: 'An entire civilization, Operator. And they want to TRADE with us. Do you realize what this means?' },
      { speaker: 'MERCHANT', text: 'It means business is about to get very, very interesting.' },
      { speaker: 'YOU', text: 'Open the channels. All of them. This changes everything.' },
    ],
  },
  {
    level: 29,
    title: 'THE ACCORD',
    lines: [
      { speaker: 'AI_CORE', text: 'The Crystalline Accord has been signed. Thirty-seven mining stations and the Builder civilization, united.' },
      { speaker: 'AI_CORE', text: 'Helix Corporation has been dissolved by interstellar tribunal. Their assets redistributed to the network.' },
      { speaker: 'POOL_LEAD', text: 'From a single node in a forgotten station to the architects of first contact. Not bad, Operator.' },
      { speaker: 'YOU', text: 'This is just the beginning.' },
    ],
  },
  {
    level: 30,
    title: 'BEYOND THE GATE',
    lines: [
      { speaker: 'AI_CORE', text: 'Operator, new sectors have been charted beyond the gate. Twelve star systems, rich with resources we have never seen.' },
      { speaker: 'AI_CORE', text: 'The Builders call them "The Infinite Veins." They say no one has ever fully mapped them.' },
      { speaker: 'YOU', text: 'Then we will be the first.' },
      { speaker: 'AI_CORE', text: 'Initiating deep space protocols. Station fully operational. All nodes online. The void awaits, Commander.' },
      { speaker: 'COMMAND', text: '[ END OF CHAPTER ONE ]' },
    ],
  },
];
