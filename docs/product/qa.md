# Product Q&A

Clarifications to the [high-level spec](high-level-spec.md), recorded as questions come up.

## Where does voice turn into text?

**Asked:** 2026-09-27

**Question:** For voice messages and live calls, who handles the audio: the agent, or the Assistant Link service (doing speech-to-text / text-to-speech and passing text to the agent)?

**Answer (MVP):** The agent is fully responsible for handling audio. Assistant Link transports audio; it does not transcribe or synthesize speech. The agent can:

- receive an audio file (a voice message from the user),
- send an audio file (a voice message reply),
- connect to a live audio stream (a call), using whatever audio infrastructure it has.

Some LLM APIs accept live audio streams directly, in which case there may be no STT/TTS step at all.
