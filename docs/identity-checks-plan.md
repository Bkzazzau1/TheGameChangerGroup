# Identity checks plan

Started on 12 October 2026 from a review of PVC scanning, fingerprint and face
security. We will do every item below, roughly in this order. Tick each one
off here when it lands.

## Who must be verified

Decided on 12 October 2026, so that joining stays simple for people who find
forms hard:

- **Members: nobody.** Every member gets the whole member app, verified or
  not, and their membership card is valid.
- **Agents and observers: always.** Their accounts work only for a member
  whose identity a coordinator has checked. Until then, a member listed as
  an agent gets the member app with a note that the work starts after the
  check.
- **Anyone given a role: always.** Roles are given only to verified members,
  and stop if verification is withdrawn.

## Done on 12 October 2026

- [x] **PVC reading.** The reader takes only a VIN of exactly 19 letters and
  digits, reads labels as whole words (so "DIVINE" in an address or a "VOTER
  CARD" heading can no longer produce a VIN), joins SURNAME with OTHER (or
  FIRST and MIDDLE) NAMES, and also reads date of birth, gender and
  occupation. Registration lists what was read, asks the member to check it
  against the card, and names anything left to type.
- [x] **Browsers and desktops.** Where the app cannot read text from a photo,
  registration says so and asks for the details to be typed.
- [x] **No "verified" tick for a scan.** Member Enrolment in the operations
  app shows a scan as a scan, and says when no text was read.
- [x] **Selfie face check on the phone.** Registration checks for exactly one
  face, looking at the camera with eyes open. After two failed photos the
  member can keep one anyway, because the check can be wrong. The server does
  not rely on it, and coordinators still review every new member.
- [x] **Joining by USSD, on the server.** Any phone can join by dialling a
  code, once item 2 is done: name, the DELIM code from the PVC, gender,
  optional date of birth and VIN, and a PIN for the app. The network supplies
  the phone number, so no SMS code is needed. See the backend's
  `docs/ussd-registration.md`.

## Next

1. [ ] **Turn on SMS codes on the live server.** Nobody can finish
   registering in the app, alone or with a coordinator, until this is done.
   *Needs:* a Termii account, `TERMII_API_KEY` and an approved
   `TERMII_SENDER_ID` in the server's environment, then removing the
   temporary 503 blocks described in [vps-deployment.md](vps-deployment.md).
2. [ ] **Turn on joining by USSD on the live server.**
   *Needs:* a USSD code from a licensed aggregator, `USSD_CALLBACK_TOKEN` and
   `USSD_SERVICE_CODE` in the server's environment, the callback URL given to
   the aggregator, Nginx letting only the aggregator's addresses reach it, and
   a test on every network.
3. [ ] **Let members who joined by USSD add their selfie and PVC**, in the app
   or with a coordinator. They are full members without it, but a coordinator
   cannot verify them for agent work or a role until they have one.
4. [ ] **Make a verified member an agent from the app.** Approving an agent's
   accreditation should give the member's own account the agent role at
   their polling unit. Today that is done by hand in the Django admin.
5. [ ] **Try scanning real PVCs on Android and iPhone**, and tune the reader to
   what the phones actually return. Use a few cards with their owners'
   consent, and keep their photos and text out of the repository.
   *Needs:* a phone build of the app and a few volunteers.
6. [ ] **Member Enrolment creates real members.** It now keeps new members
   only in the app on that device and drops the VIN and polling unit. It
   should use the server's coordinator-assisted registration, which already
   exists and takes the PVC, the selfie and the member's SMS code.
7. [ ] **Check selfies for a face on the server as well.** A browser or a
   modified app can skip the phone's check. A server check covers every
   registration, and its result can be recorded as a check the system
   performed.
8. [ ] **Liveness check on the phone.** Ask the member to blink or turn their
   head while the camera watches, so a printed photo cannot pass. Like the
   face check, this improves the capture; the server cannot rely on it.
9. [ ] **Lock the agent app with the phone's fingerprint or face unlock.** This
   shows that the phone's owner opened the app. The app never sees the
   fingerprint, so it cannot identify anyone.
10. [ ] **Remove the manual "Biometric enrollment recorded" switch.** The
   "Biometric" counts and the "Identity" tick on agent cards come from it,
   though nothing is captured. Show real status from the server, or nothing.
11. [ ] **Label the AI Verification screen in presentation mode.** Its "Face
    match 97.9%" and "Liveness passed" are fixed example text. It shows the
    "Demo data" notice only when signed in to the live server.
12. [ ] **Show in Member Review how each member joined**: in the app, with a
    coordinator, or by USSD.
13. [ ] **Read PVC text from photos added in a browser** (optional), with text
    recognition on the server.

## Needs an outside source or equipment

14. [ ] **Match faces against a trusted photo.** The photo printed on a PVC is
    not a trusted reference. NIN records through a NIMC-licensed verification
    provider would be.
    *Needs:* a provider contract and access keys (kept in the server's
    environment, never in the code), consent wording, and a data protection
    review: biometric data is sensitive personal data under the Nigeria Data
    Protection Act 2023.
15. [ ] **Fingerprint identification.** A phone's sensor cannot identify
    people. This needs fingerprint scanners for coordinators and a matching
    service, or NIN biometric verification through a provider.
    *Needs:* the equipment, a provider, and the same consent and data
    protection work as item 14.
16. [ ] **Confirm PVCs against INEC's records.** We have no authorised INEC
    service to check a card against. Until there is one, the server keeps
    recording "PVC confirmed with an authoritative source" as not available.

## Rules that stay

- A check counts as passed only when the server or a trusted provider
  performed it. Checks on the phone help people take good photos; the server
  never treats them as verification.
- Reading a PVC is not validating it, and a selfie alone is not biometric
  verification.
- No real member's card photo, PVC text or selfie goes into the repository,
  the tests or the logs.
