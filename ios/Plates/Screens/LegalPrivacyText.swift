import Foundation

/// The Privacy Policy, verbatim.
///
/// Kept apart from `LegalScreen` on purpose. That file decides how a document
/// looks; this one is the document. They change for entirely different reasons and
/// at entirely different times, and a typography tweak should never sit in the same
/// diff as a change to a data-retention clause.
///
/// **Section 2 is the one that has to track the code.** The rest of this policy is
/// written broadly, to cover the Service as it grows. Section 2 says what the build
/// actually does: which permissions it asks for, where audio goes when the phone
/// cannot transcribe it, what leaves the device over the local network, what Apple
/// holds and what we hold, which is nothing. It declares itself controlling over the
/// general language wherever the two disagree, so it is the section a reader relies
/// on and therefore the section that is wrong the moment somebody adds an SDK
/// without touching this file. Anyone changing what the app collects, transmits or
/// asks permission for edits Section 2 in the same commit.
extension Legal {
    static let privacy: [Block] = [
        .body(#"This Privacy Policy explains how TAGs Media LLC ("TAGS," "we," "us," or "our") collects, uses, discloses, and protects information when you use TAGS: The License Plate Game, our related websites, and associated services (collectively, the "Service")."#),
        .body(#"By using the Service, you acknowledge the practices described here. If you do not agree, do not use the Service. This Policy should be read together with our Terms and Conditions."#),

        .sub("What TAGS does today"),
        .body(#"This version of TAGS has no user accounts, no advertising, no analytics or tracking software, and no TAGS servers. What you record stays on your device and, if you have iCloud turned on, in your own private Apple iCloud account, which we cannot read. Shared books and parties send what you choose to share directly to the people you invite, through Apple's services or your local network. The sections below are written to cover the Service as it grows, including features such as accounts, purchases, and advertising that are described here but are not present in the current version. Where a section describes something TAGS does not yet do, it does not apply to you until we do it and update the effective date above. Section 2 sets out in detail how the current version actually handles information."#),

        .heading("1. Information We Collect"),
        .sub("Information you provide"),
        .bullet(#"Account information, such as your name, email address, username, profile details, password or authentication credentials, home state, and friend or invite codes."#),
        .bullet(#"Game and social information, including trips, books, plate sightings, scores, badges, battles, friends, shared trips, reactions, reports, and other interactions."#),
        .bullet(#"User content, including photos, captions, notes, trip memories, and other material you upload, create, share, or make public."#),
        .bullet(#"Communications, including support requests, feedback, contest entries, and reports of users or content."#),
        .sub("Information collected automatically"),
        .bullet(#"Location information. With your permission, we collect precise location information to map trip trails, associate sightings or memories with places, support location-based rarity or gameplay, and provide related features. Location may be collected while you actively use the Service and, only if you separately authorize it and the feature requires it, in the background."#),
        .bullet(#"Audio and speech information. With your permission, we capture audio through your device's microphone while a voice feature is active and convert it to text in order to record the plates you call out."#),
        .bullet(#"Device and usage information, such as device type, operating system, app version, language, IP address, identifiers, screens viewed, taps, session times, referring information, and feature usage."#),
        .bullet(#"Diagnostics, such as crash reports, performance data, error logs, and technical events."#),
        .bullet(#"Notification information, including a push-notification token and your notification preferences."#),
        .bullet(#"Advertising information, which may include advertising identifiers, approximate location derived from IP address, ad interactions, and information used to measure, limit, personalize, or attribute advertising, subject to your settings and applicable consent requirements."#),
        .bullet(#"Purchase and subscription information, such as the product or feature purchased, transaction or receipt identifiers, entitlement status, subscription status, and renewal, cancellation, or refund information. Payments are processed by the applicable app store or payment provider; TAGS does not receive your complete payment-card information from the app store."#),
        .sub("Information from others"),
        .body(#"We may receive information from authentication providers, analytics and crash-reporting vendors, advertising partners, app stores, other users who invite or interact with you, and service providers that help operate the Service."#),

        .heading("2. Device Permissions, Apple Services, and On-Device Processing"),
        .body(#"This section describes how the current version of the Service handles information on your device and through services operated by Apple Inc. To the extent this section conflicts with a general description elsewhere in this Policy, this section controls with respect to the current version of the Service."#),

        .sub("What a sighting is"),
        .body(#"A sighting recorded in the Service consists of the state, province, or territory that issued a license plate, the time the sighting was recorded, the trip or book it was recorded in, the player who recorded it, the rarity value assigned at that time, and, where location permission has been granted, the position of your device at that time. The Service provides no facility to enter, capture, photograph, or store a plate's registration number, a vehicle identification number, a description of a vehicle, or any information about a vehicle's owner or occupants, and it does not record any of those things."#),

        .sub("Location"),
        .body(#"If you grant location permission, the Service uses your device's location while a trip is open in order to advance the vehicle along your route, to calculate how rare a plate is relative to where you are, and to record the position at which you logged a sighting so that the Trail feature can map it. Recorded positions are stored on your device and, where iCloud is enabled, in your private iCloud database. Positions are removed from a sighting before that sighting is transmitted to another person through a shared book or a party, and TAGS does not receive them. A recorded position is retained for as long as the sighting it belongs to exists and is deleted with it. You may withdraw location permission at any time in your device settings, which will limit the Trail, distance-weighted rarity, and related features."#),

        .sub("Microphone and speech recognition"),
        .body(#"If you enable voice mode and grant microphone and speech recognition permission, the Service captures audio while voice mode is active and converts that audio to text in order to identify the plates you call out. Where your device supports on-device speech recognition, the Service requires on-device recognition and the audio is not transmitted off your device. Where your device does not support on-device speech recognition, Apple performs the recognition and the audio is transmitted to Apple, subject to Apple's privacy policy. TAGS does not receive, store, or retain your audio in either case. You may withdraw either permission at any time in your device settings."#),

        .sub("Local network"),
        .body(#"The party feature uses Apple's Multipeer Connectivity framework to discover and connect to other devices running the Service on the same local network. If you start or join a party, the Service transmits your display name, your avatar, and the sightings recorded during that party directly to the other participating devices over that local network. This traffic does not pass through TAGS, and TAGS does not receive a copy of it."#),

        .sub("iCloud and shared books"),
        .body(#"Where you are signed in to iCloud and iCloud is enabled for the Service, your trips, books, sightings, and players are stored in your private iCloud database using Apple's CloudKit service, which Apple operates subject to Apple's privacy policy. TAGS cannot read the contents of your private iCloud database. If you share a book, Apple's CloudKit sharing delivers it to the people you invite, and those participants can see the plates, display names, and avatars contributed to that book. TAGS does not operate a server that stores your content and does not receive a copy of it."#),

        .sub("Notifications"),
        .body(#"The Service schedules local notifications on your device to remind you about an unfinished trip. Those notifications are generated by your device. The Service does not register for remote push notifications and TAGS does not maintain a push notification token for you. Apple's CloudKit service may use silent push notifications to keep your own devices in sync with one another."#),

        .sub("Siri and Shortcuts"),
        .body(#"The Service exposes App Intents so that you can record a sighting or ask about your collection using Siri or the Shortcuts app. Requests you make to Siri are handled by Apple subject to Apple's privacy policy. TAGS receives only the resulting instruction to record or to read information already stored on your device."#),

        .sub("Home screen widget"),
        .body(#"The Service writes a summary of your current trip and collection to a shared container on your device so that the home screen widget can display it. That summary remains on your device."#),

        .sub("Reporting and blocking"),
        .body(#"If you report another person, the Service prepares an email message addressed to TAGS containing the display name of the person you are reporting, an internal reference identifier for that person, the reason you selected, any description you choose to add, and the version of the Service you are using. Nothing is transmitted to us until you send that message from your own mail application, and your mail application supplies your return address. If you block another person, the block and the concealment of that person's contributions take effect on your device."#),

        .sub("What the current version does not do"),
        .body(#"The current version of the Service contains no advertising software development kit, no analytics or attribution software development kit, no crash-reporting service, no third-party software libraries, no in-app purchase or subscription functionality, and no facility for uploading photographs. It does not request permission under Apple's AppTrackingTransparency framework, because it performs no tracking. It does not collect your name, email address, password, IP address, advertising identifier, or device identifier."#),

        .heading("3. How We Use Information"),
        .bullet(#"Provide, personalize, maintain, and improve the Service and its gameplay, maps, trip history, social and sharing features."#),
        .bullet(#"Create and administer accounts; authenticate users; sync activity; and deliver notifications you request or permit."#),
        .bullet(#"Display content to the audiences you select and facilitate friends, battles, shared trips, and other social interactions."#),
        .bullet(#"Calculate plate rarity, scores, achievements, trends, and aggregated insights."#),
        .bullet(#"Measure performance, troubleshoot, develop features, perform research, and understand how the Service is used."#),
        .bullet(#"Serve, measure, and improve advertising and affiliate content, subject to applicable law and your choices."#),
        .bullet(#"Process, verify, fulfill, restore, and support optional purchases or subscriptions; maintain entitlements; prevent purchase fraud; and meet accounting, tax, and legal obligations."#),
        .bullet(#"Prevent fraud, abuse, unsafe activity, and violations of our Terms; moderate content; investigate reports; and protect users and the Service."#),
        .bullet(#"Comply with law, enforce agreements, establish or defend legal claims, and communicate important administrative or security information."#),

        .heading("4. Location, Photos, and Public Sharing"),
        .body(#"Precise location and photos can reveal where you live, travel, or spend time. Before sharing a trip, trail, sighting, photo, or note, review the audience and remove anything you do not want others to see. Content you make public may be viewed, copied, saved, or reshared by others outside our control."#),
        .body(#"You can change location permissions in your device settings. Disabling location may limit mapping, trail, rarity, or other gameplay features. You can manage photo access through your device settings and delete eligible content in the Service or by contacting us."#),
        .body(#"Do not upload a photo that exposes a person's private information, depicts a minor without appropriate permission, or violates law or another person's rights. Where technically feasible, TAGS may remove embedded photo metadata before public display, but you should not rely on that process as your only protection."#),

        .heading("5. How We Disclose Information"),
        .bullet(#"Other users and the public. Your profile, username, game activity, scores, shared trips, photos, notes, or other content may be visible based on the feature and audience you choose."#),
        .bullet(#"Service providers. We disclose information to vendors that provide hosting, databases, authentication, email, notifications, analytics, crash reporting, security, moderation, customer support, and similar services."#),
        .bullet(#"Advertising and affiliate partners. We may disclose identifiers, device or usage information, approximate location, and ad interactions to deliver and measure ads or affiliate content. We do not disclose your precise trip trail to advertisers unless we first provide clear notice and obtain any consent required by law."#),
        .bullet(#"App stores and payment providers. We exchange transaction identifiers, product information, entitlement status, and related purchase information with the applicable app store or payment provider to process, verify, restore, support, or refund purchases and subscriptions."#),
        .bullet(#"Legal and safety recipients. We may disclose information to comply with law or legal process; investigate fraud, abuse, security, or safety issues; enforce our agreements; or protect rights and property."#),
        .bullet(#"Business transfers. Information may be disclosed in connection with financing, due diligence, merger, acquisition, reorganization, sale of assets, bankruptcy, or similar transaction."#),
        .bullet(#"With your direction or consent. We disclose information when you direct us to do so or otherwise consent."#),
        .body(#"We do not sell personal information for money. Some advertising disclosures may be considered a "sale," "sharing," or targeted advertising under certain state laws. Where required, we provide a method to opt out. As described in Section 2, the current version of the Service discloses no information to advertising or analytics partners, because it uses none, and it does not sell or share personal information within the meaning of any state privacy law, so there is no opt-out for it to honor. Where our website processes personal information in a manner that would require an opt-out, it will treat a Global Privacy Control signal from your browser as a valid request to opt out."#),

        .heading("6. Advertising, Tracking, and Your Choices"),
        .body(#"We may use third-party advertising or analytics technologies. On Apple devices, we will request permission through Apple's AppTrackingTransparency framework before tracking where required. You may deny or later change that permission in device settings. You may also limit personalized advertising through device settings and any in-app privacy controls we provide. Contextual ads may still appear."#),
        .body(#"If you purchase an ad-free upgrade, we will not display in-app advertisements while the applicable entitlement remains active. The upgrade does not disable non-advertising analytics, diagnostics, security functions, purchase verification, or other data processing described in this Policy."#),
        .body(#"Affiliate links may allow us to receive compensation when you click a link or complete a transaction. The third party's privacy policy applies to information it collects after you leave the Service."#),

        .heading("7. Data Retention"),
        .body(#"We retain account information and user content while your account is active and as reasonably necessary to provide the Service. If you delete content or your account, we generally remove or de-identify eligible information from active systems within 30 days, although residual copies may remain in backups for up to 90 days. We may retain information longer when reasonably necessary for security, fraud prevention, dispute resolution, legal compliance, enforcement, or to maintain a record of consent. We may retain transaction and entitlement records as reasonably necessary to provide purchased features and comply with accounting, tax, fraud-prevention, and legal obligations. Aggregated or de-identified information may be retained indefinitely."#),
        .body(#"In the current version of the Service, TAGS operates no system that holds your account information or your user content, and the periods described above therefore apply only to information TAGS actually receives from you, such as a report, a support request, or other correspondence you send to us."#),

        .heading("8. Your Rights and Controls"),
        .body(#"Depending on where you live, you may have rights to access, correct, delete, or obtain a copy of personal information; opt out of certain sales, sharing, targeted advertising, or profiling; limit certain uses of sensitive information; withdraw consent; and appeal a denied request. You may also manage location, microphone, speech recognition, local network, photo, notification, and tracking permissions through device settings."#),
        .body(#"To exercise a right, write to privacy@playtagsnow.com. We may need to verify your identity, and we will do so using only information reasonably necessary for that purpose. We will respond to a verifiable request within 45 days of receiving it, and may extend that period once by a further 45 days where reasonably necessary, in which case we will tell you. Authorized agents may submit requests where permitted by law. We will not discriminate against you for exercising a privacy right. In the current version of the Service, TAGS is unlikely to hold any personal information about you other than correspondence you have sent to us, and we will tell you so in response to a request."#),

        .heading("9. Deleting Your Information"),
        .body(#"The current version of the Service does not create an account for you and does not store your content on any system operated by TAGS, so deletion is within your control. You may delete a trip, a book, or an individual sighting within the Service. You may delete all content held locally by deleting the app from your device. Content held in your private iCloud database is managed through your Apple Account and may be removed through your device's iCloud settings. If you leave or delete a shared book, plates you contributed may remain visible to the other participants, because each participant holds their own copy, and a participant who has copied or reshared content may retain it."#),
        .body(#"If TAGS later holds personal information about you, you may request its deletion by writing to privacy@playtagsnow.com, and we may retain limited information as described in Section 7. Deleting the app does not by itself delete content held in your iCloud account."#),

        .heading("10. Children's Privacy"),
        .body(#"The Service is offered to a general audience, including families playing together in a vehicle, and is not directed to children under 13 within the meaning of the Children's Online Privacy Protection Act. As described in Section 2, the current version of the Service does not require an account, transmits no personal information to TAGS, and uses no advertising, analytics, or tracking technology. TAGS accordingly does not knowingly collect personal information from any user, including a child under 13."#),
        .body(#"If TAGS later introduces a feature that collects personal information, we will not knowingly collect that information from a child under 13 without verifiable parental consent where the law requires it. A parent or guardian who believes that a child under 13 has provided personal information to us should contact privacy@playtagsnow.com, and we will take reasonable steps to delete it."#),
        .body(#"A parent or legal guardian is responsible for supervising a minor's use of the Service, including any display name or avatar the minor chooses and any shared book or party in which the minor participates. Content a minor shares through a shared book or a party is transmitted to the other participants who were invited. Do not upload or share images of children without appropriate authorization."#),

        .heading("11. Security"),
        .body(#"We use reasonable administrative, technical, and organizational safeguards designed to protect information. No security measure or transmission method is completely secure, and we cannot guarantee absolute security. Information the Service stores on your device is protected by the security of that device and of your Apple Account, which you control. Keep your credentials confidential and notify us if you suspect unauthorized access."#),

        .heading("12. International Use"),
        .body(#"TAGS is operated from the United States. If you use the Service elsewhere, information you send to us may be transferred to and processed in the United States and other countries where we or our service providers operate, subject to applicable safeguards. Information the Service keeps on your device or in your iCloud account is stored by Apple in the locations Apple designates."#),

        .heading("13. Third-Party Services"),
        .body(#"The Service relies on services operated by Apple, including iCloud, CloudKit sharing, speech recognition, Siri, and the App Store, and may link to or integrate with other third-party services. Their privacy practices are governed by their own policies, not this Policy. Review those policies before providing information."#),

        .heading("14. Changes to This Policy"),
        .body(#"We may update this Policy. We will post the revised version and change the effective date. If changes are material, we will provide additional notice as required by law, and the Service will ask you to read and acknowledge the updated Policy before you continue using it. Your continued use after the effective date of an update means the updated Policy applies to your use, to the extent permitted by law. Each edition of this Policy is identified by its effective date and by a document fingerprint displayed in the Legal section of the Service and on our website, so that you can identify the edition you acknowledged."#),

        .heading("15. Contact Us"),
        .contact("""
        TAGs Media LLC
        privacy@playtagsnow.com
        www.PlayTAGsNow.com
        """)
    ]
}
