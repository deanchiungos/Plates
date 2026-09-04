import Foundation

/// The Terms and Conditions, verbatim. See `LegalPrivacyText` for why the text
/// lives apart from the view that draws it.
extension Legal {
    static let terms: [Block] = [
        .body(#"These Terms and Conditions ("Terms") are a binding agreement between you and TAGs Media LLC ("TAGS," "we," "us," or "our") governing your access to and use of TAGS: The License Plate Game and related services (collectively, the "Service")."#),
        .body(#"By tapping Agree in the Service, or by downloading, accessing, or using the Service, you agree to these Terms and our Privacy Policy. If you do not agree, do not use the Service."#),
        .caps(#"IMPORTANT: SECTION 19 CONTAINS AN AGREEMENT TO RESOLVE DISPUTES BY BINDING INDIVIDUAL ARBITRATION AND A WAIVER OF CLASS ACTIONS AND JURY TRIALS. IT AFFECTS YOUR RIGHTS. YOU MAY OPT OUT WITHIN 30 DAYS AS DESCRIBED IN SECTION 19."#),

        .sub("Scope of the current version"),
        .body(#"The current version of the Service does not require or offer user accounts, does not display advertising, does not offer in-app purchases or subscriptions, and does not permit the upload of photographs. Several provisions below address accounts, purchases, advertising, and user-uploaded media so that these Terms continue to govern as the Service develops. A provision describing a feature the Service does not offer has no application to you unless and until that feature becomes available and the effective date above is updated. Section 2 of our Privacy Policy describes how the current version actually handles information."#),

        .heading("1. Eligibility"),
        .body(#"The Service is offered to a general audience and does not require an account. If you are under the age of majority where you live, you may use the Service only with the permission and supervision of a parent or legal guardian, who agrees to these Terms on your behalf and is responsible for your use of the Service. You may use the Service only if you are legally permitted to do so."#),
        .body(#"If TAGS later offers user accounts, you must provide accurate information, keep it current, protect your credentials, and promptly notify us of suspected unauthorized access. You would be responsible for activity through your account, and you may not sell, transfer, or share an account in a way that compromises security or circumvents these Terms."#),

        .heading("2. The Service"),
        .body(#"TAGS is an entertainment game that allows users to record license-plate sightings, create trips and books, calculate scores and rarity, review past trips on a map, and share a book or join a party with other people. TAGS may add further features, including social or competitive features, over time. Features, availability, scoring, rarity values, and content may change."#),
        .body(#"The Service does not guarantee that any plate, location, rarity assessment, score, map, trail, route, or other information is accurate, complete, or current. TAGS is not a navigation, emergency, traffic-safety, or law-enforcement service."#),

        .heading("3. Drive Safely"),
        .caps("NEVER USE TAGS WHILE DRIVING. A PASSENGER MAY RECORD A SIGHTING, OR THE DRIVER MUST WAIT UNTIL LEGALLY PARKED IN A SAFE LOCATION."),
        .body(#"You must obey traffic laws, remain attentive, and use the Service only when it is safe and lawful. The availability of a hands-free or voice-controlled feature does not make it safe or lawful to use the Service while driving, and you remain solely responsible for compliance with the traffic and distracted-driving laws that apply to you. Do not photograph, enter, verify, or search for plates while operating a vehicle. Do not stop, slow, follow, approach, confront, or otherwise endanger anyone to record a plate. Do not trespass or enter restricted or unsafe areas. You expressly assume all risk of injury, death, property damage, citation, fine, or other liability arising from use of the Service in or around a vehicle, whether by you or by another person using your device, and you acknowledge that TAGS has no ability to monitor or control how or where the Service is used."#),

        .heading("4. License to Use the Service"),
        .body(#"Subject to these Terms, TAGS grants you a limited, personal, revocable, non-exclusive, non-transferable, non-sublicensable license to access and use the Service for lawful, noncommercial entertainment. All rights not expressly granted are reserved."#),

        .heading("5. Acceptable Use"),
        .body("You may not:"),
        .bullet(#"Violate law, traffic rules, privacy rights, publicity rights, intellectual-property rights, or another person's rights."#),
        .bullet(#"Use the Service to identify, locate, track, stalk, harass, threaten, surveil, profile, or target a person or vehicle."#),
        .bullet(#"Publish a plate image or location together with accusations, sensitive personal information, or content that creates a safety or privacy risk."#),
        .bullet(#"Record, store, or transmit through the Service a vehicle registration number, a vehicle identification number, or the identity of a vehicle's owner or occupant, or attempt to use the Service to obtain such information. The Service records only the state, province, or territory that issued a plate and provides no facility for anything more."#),
        .bullet(#"Upload unlawful, infringing, deceptive, hateful, sexually exploitative, violent, threatening, defamatory, or otherwise objectionable material."#),
        .bullet(#"Impersonate another person; misrepresent affiliation; manipulate gameplay, rarity, scores, contests, or engagement; create fraudulent sightings; or use bots or automation."#),
        .bullet(#"Collect or scrape information about users; reverse engineer or interfere with the Service; bypass security, moderation, rate limits, or access controls; or introduce malware."#),
        .bullet(#"Use the Service or its data for law enforcement, insurance, employment, housing, credit, eligibility, or other high-impact decisions without our express written authorization."#),
        .bullet(#"Use TAGS branding, content, data, or the Service commercially except as expressly permitted by us in writing."#),

        .heading("6. User Content"),
        .body(#""User Content" means photos, captions, notes, usernames, trip information, comments, reports, and other material you submit or share. You retain ownership of your User Content. You represent that you have all rights and permissions needed to submit it and that it complies with these Terms."#),
        .body(#"You grant TAGS a worldwide, non-exclusive, royalty-free, sublicensable, and transferable license to host, store, reproduce, format, adapt, display, distribute, and otherwise use your User Content only as reasonably necessary to operate, provide, secure, moderate, improve, and promote the Service. This license ends when the User Content is deleted from our active systems, except where content has been shared with others, retained for legal or safety reasons, or incorporated into de-identified or aggregated materials."#),
        .body(#"Do not upload content containing confidential information, precise home locations, children's images without permission, or other material you do not want the intended audience to access. Public content may be copied or reshared by others."#),

        .heading("7. Moderation, Reporting, and Blocking"),
        .body(#"We may, but are not obligated to, monitor, review, restrict, remove, preserve, or disclose User Content or activity that we reasonably believe violates these Terms, presents risk, or is otherwise objectionable. We may use automated tools and human review. Our failure to remove content does not endorse it."#),
        .body(#"Users can report inappropriate content or conduct and can block other users using the reporting and blocking features available within the Service. Selecting a report reason prepares a message addressed to TAGS from your own mail application, and the report reaches us only when you send that message; it identifies the person reported, the reason selected, and any description you add. Blocking a person conceals that person's contributions on your device and causes the Service to refuse further content from them, and you may reverse a block at any time. We may investigate reports and take action including warnings, content removal, feature restrictions, suspension, or termination. Contact support@playtagsnow.com for urgent safety or moderation concerns. If someone faces immediate danger, contact local emergency services."#),

        .heading("8. Sharing With Other Users"),
        .body(#"The Service allows you to share a book with people you invite through Apple's iCloud sharing, and to join a party with people using the Service on the same local network. Sharing a book or joining a party exposes your display name, your avatar, and the plates you record to the other participants. Review the audience and the settings before you share, and invite only people you know. TAGS may later offer friend connections, battles, leaderboards, or other social features that expose the same information to a wider audience."#),
        .body(#"You are responsible for your interactions with other users. Use judgment, and do not meet strangers or disclose personal information based solely on an in-app interaction."#),

        .heading("9. Advertising, Affiliate Links, and Third Parties"),
        .body(#"The Service may display advertisements, sponsored content, or affiliate links. We may receive compensation from advertising or affiliate partners. TAGS does not control and is not responsible for third-party products, content, websites, services, representations, transactions, or privacy practices. Your dealings with third parties are between you and them."#),

        .heading("10. Optional In-App Purchases and Subscriptions"),
        .body(#"TAGS is free to download. We may offer optional in-app purchases, paid upgrades, consumable digital items, virtual items, subscriptions, or other paid features. The price, included benefits, billing period, and any material limitations will be displayed before you complete a purchase."#),
        .body(#"Optional paid upgrades may include a one-time, non-consumable purchase that removes advertisements while the applicable entitlement remains active. Unless the purchase screen expressly states otherwise, an ad-free upgrade removes displayed advertisements but does not disable non-advertising analytics, diagnostics, security functions, purchase verification, or other data processing described in our Privacy Policy."#),
        .body(#"Purchases are processed by the applicable app store or payment provider, such as Apple or Google, and are also subject to that provider's terms, billing rules, cancellation procedures, and refund policies. Except where required by law or the applicable store, purchases are final and nonrefundable. TAGS does not receive your complete payment-card information from the app store."#),
        .body(#"Non-consumable purchases may be restored where supported. Consumable items are depleted when used, have no cash value, may not be transferred or exchanged outside the Service, and generally cannot be restored after consumption. All purchased features and virtual items are licensed, not sold, and may be used only with the Service."#),
        .body(#"If we offer an auto-renewing subscription, it will renew and the applicable store account will be charged unless you cancel through your store account before the renewal deadline shown by the store. Any free or discounted trial may convert to a paid subscription unless canceled before the trial ends. You can manage or cancel a subscription through the applicable app-store settings. Cancellation ordinarily takes effect at the end of the current paid period unless the store or applicable law provides otherwise."#),
        .body(#"We may add, modify, or discontinue purchasable offerings, but doing so does not limit any refund, restoration, cancellation, or other right required by law or app-store rules. If a price changes, any notice or consent required by the applicable store or law will apply."#),

        .heading("11. TAGS Content and Intellectual Property"),
        .body(#"The Service, including software, interface, designs, artwork, graphics, text, compilation, gameplay systems, scoring methods, databases, and TAGS names and marks, is owned by TAGS or its licensors and protected by law. License plates, government emblems, team marks, maps, or other third-party materials may belong to their respective owners. No affiliation or endorsement is implied unless expressly stated."#),

        .heading("12. Copyright Complaints and DMCA Notices"),
        .body(#"If you believe material available through the Service infringes your copyright, send a written notice to our designated copyright agent at legal@playtagsnow.com. The notice should identify the copyrighted work, identify the allegedly infringing material and where it appears, provide your contact information, state your good-faith belief that the disputed use is not authorized, state under penalty of perjury that the notice is accurate and that you are authorized to act, and include your physical or electronic signature."#),
        .body(#"If your User Content is removed in response to a copyright notice and you believe the removal was mistaken or misidentified, you may send a counter-notice to the same agent. The counter-notice should identify the removed material and its prior location, state under penalty of perjury your good-faith belief that it was removed by mistake or misidentification, provide your name, address, and telephone number, consent to the jurisdiction of the appropriate United States federal court, accept service of process from the notifying party, and include your physical or electronic signature."#),
        .body(#"We may forward notices and counter-notices to the affected parties and may remove or restore material as permitted by law. We may terminate accounts of repeat infringers in appropriate circumstances. Knowingly submitting a materially false notice or counter-notice may result in liability. This process does not constitute legal advice."#),

        .heading("13. Feedback"),
        .body(#"If you provide suggestions or feedback, you grant us a perpetual, irrevocable, worldwide, royalty-free right to use it without restriction or compensation, provided we do not publicly identify you as its source without permission."#),

        .heading("14. Suspension and Termination"),
        .body(#"You may stop using the Service at any time by deleting the app from your device; our Privacy Policy describes how to delete the content it holds. If TAGS later offers user accounts, you may request deletion of yours by writing to support@playtagsnow.com. We may suspend, restrict, or terminate access, remove content, or discontinue all or part of the Service if we reasonably believe you violated these Terms, created risk, or if needed for legal, security, operational, or business reasons. Where appropriate, we will provide notice."#),
        .body(#"Provisions that by their nature should survive termination, including ownership, licenses already granted, disclaimers, limitations of liability, indemnity, and dispute provisions, will survive."#),

        .heading("15. Changes and Availability"),
        .body(#"We may add, remove, modify, suspend, or discontinue features, scoring, data, social functions, or the Service. We do not guarantee uninterrupted or error-free access, preservation of any trip or content, or compatibility with every device. Back up content important to you."#),

        .heading("16. Disclaimer of Warranties"),
        .caps(#"TO THE MAXIMUM EXTENT PERMITTED BY LAW, THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE." TAGS AND ITS AFFILIATES, LICENSORS, AND SERVICE PROVIDERS DISCLAIM ALL WARRANTIES, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, NON-INFRINGEMENT, ACCURACY, AVAILABILITY, SECURITY, AND QUIET ENJOYMENT. SOME JURISDICTIONS DO NOT ALLOW CERTAIN DISCLAIMERS, SO SOME OF THIS SECTION MAY NOT APPLY TO YOU."#),

        .heading("17. Limitation of Liability"),
        .caps("TO THE MAXIMUM EXTENT PERMITTED BY LAW, TAGS AND ITS AFFILIATES, OFFICERS, EMPLOYEES, AGENTS, LICENSORS, AND SERVICE PROVIDERS WILL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, OR FOR LOST PROFITS, DATA, GOODWILL, OR BUSINESS, ARISING FROM OR RELATED TO THE SERVICE, EVEN IF ADVISED OF THE POSSIBILITY."),
        .caps("TO THE MAXIMUM EXTENT PERMITTED BY LAW, THEIR TOTAL AGGREGATE LIABILITY FOR ALL CLAIMS ARISING FROM OR RELATED TO THE SERVICE WILL NOT EXCEED THE GREATER OF (A) $100 OR (B) THE AMOUNT YOU PAID TAGS, IF ANY, DURING THE 12 MONTHS BEFORE THE EVENT GIVING RISE TO THE CLAIM. THESE LIMITATIONS DO NOT APPLY WHERE PROHIBITED BY LAW."),
        .body(#"Nothing in these Terms excludes or limits liability for death or personal injury caused by negligence, for fraud or fraudulent misrepresentation, or for any other liability that cannot be excluded or limited under applicable law. The exclusions and limitations in this Section and in Section 16 apply to the fullest extent the law allows and no further, and each is intended to be severable from the others."#),

        .heading("18. Indemnification"),
        .body(#"To the maximum extent permitted by law, you agree to defend, indemnify, and hold harmless TAGS and its affiliates, officers, employees, agents, licensors, and service providers from claims, damages, losses, liabilities, costs, and expenses (including reasonable attorneys' fees) arising from your User Content, your misuse of the Service, your violation of these Terms or law, or your violation of another person's rights. This obligation does not apply to the extent a claim results from TAGS's own unlawful conduct."#),

        .heading("19. Dispute Resolution, Arbitration Agreement, and Class Action Waiver"),
        .caps(#"PLEASE READ THIS SECTION CAREFULLY. IT REQUIRES YOU AND TAGS TO RESOLVE MOST DISPUTES THROUGH BINDING INDIVIDUAL ARBITRATION RATHER THAN IN COURT, AND IT WAIVES THE RIGHT TO BRING OR PARTICIPATE IN A CLASS ACTION AND THE RIGHT TO A JURY TRIAL. YOU MAY OPT OUT AS DESCRIBED UNDER THE HEADING "OPTING OUT" BELOW."#),

        .sub("Informal resolution first"),
        .body(#"Before beginning an arbitration or a lawsuit, the party raising a dispute must send the other party a written notice describing the dispute and the relief sought. Notice to TAGS must be sent to legal@playtagsnow.com with the subject line "Notice of Dispute". Notice to you will be sent to the email address you have used to correspond with us or, if there is none, will be posted within the Service. The parties will attempt in good faith to resolve the dispute for 60 days after the notice is received. If the dispute is not resolved within that period, either party may proceed as set out below. Any applicable limitation period is tolled while this informal resolution process is pending."#),

        .sub("Agreement to arbitrate"),
        .body(#"Except as provided under the headings "Exceptions" and "Opting out", you and TAGS agree that any dispute, claim, or controversy arising out of or relating to these Terms, the Privacy Policy, or the Service, including their formation, validity, interpretation, performance, breach, or termination, and including claims that arose before you accepted these Terms, will be resolved by binding arbitration on an individual basis. This arbitration agreement is governed by the Federal Arbitration Act, 9 U.S.C. Section 1 and following, and evidences a transaction involving interstate commerce."#),

        .sub("Rules and forum"),
        .body(#"The arbitration will be administered by the American Arbitration Association ("AAA") under its Consumer Arbitration Rules in effect when the arbitration is filed, as modified by this Section. The AAA rules are available at www.adr.org. If the AAA is unavailable or unwilling to administer the arbitration, the parties will agree on a substitute administrator, and if they cannot agree, a court of competent jurisdiction will appoint one. A single neutral arbitrator will decide the dispute. Any hearing will be conducted by video conference or telephone unless the arbitrator determines that an in-person hearing is necessary, in which case it will be held in the county where you reside or another location the parties agree on. The arbitrator may award to an individual party any relief that a court of competent jurisdiction could award to that party, and judgment on the award may be entered in any court of competent jurisdiction."#),

        .sub("Fees"),
        .body(#"Payment of filing, administrative, and arbitrator fees is governed by the AAA rules. For a claim seeking $10,000 or less, TAGS will pay all such fees, unless the arbitrator finds that the claim is frivolous or was brought for an improper purpose. Each party bears its own attorneys' fees and costs unless the arbitrator awards them under applicable law."#),

        .sub("Who decides"),
        .body(#"The arbitrator, and not any court or agency, has exclusive authority to resolve any dispute relating to the interpretation, applicability, enforceability, or formation of this arbitration agreement, including any claim that all or part of it is void or voidable, except that a court will decide any dispute about the enforceability of the class action waiver below."#),

        .sub("Class action waiver"),
        .caps(#"YOU AND TAGS AGREE THAT EACH MAY BRING CLAIMS AGAINST THE OTHER ONLY IN AN INDIVIDUAL CAPACITY, AND NOT AS A PLAINTIFF OR CLASS MEMBER IN ANY PURPORTED CLASS, COLLECTIVE, CONSOLIDATED, PRIVATE ATTORNEY GENERAL, OR REPRESENTATIVE PROCEEDING. THE ARBITRATOR MAY NOT CONSOLIDATE MORE THAN ONE PERSON'S CLAIMS OR PRESIDE OVER ANY FORM OF CLASS OR REPRESENTATIVE PROCEEDING."#),
        .body(#"If a court decides that this class action waiver is unenforceable as to a particular claim or request for relief, then that claim or request for relief, and only that claim or request for relief, will be severed from the arbitration and brought in court under the heading "Court proceedings" below, and all other claims and requests for relief will proceed in arbitration."#),

        .sub("Exceptions"),
        .body(#"Either party may bring an individual claim in small-claims court in the county where you reside or in Morris County, New Jersey, if the claim qualifies for that court and remains there. Either party may seek injunctive or other equitable relief in court to prevent infringement or misuse of its intellectual property rights. Nothing in this Section prevents you from bringing a complaint to a federal, state, or local agency, and an agency may seek relief on your behalf where the law permits."#),

        .sub("Opting out"),
        .body(#"You may opt out of this arbitration agreement and class action waiver by sending an email to legal@playtagsnow.com with the subject line "Arbitration Opt-Out" within 30 days after the date you first accept these Terms. The email must include your full name, your mailing address, and a clear statement that you wish to opt out of arbitration. An opt-out applies only to you and does not affect any other part of these Terms. If you opt out, or if this arbitration agreement is found to be unenforceable, the heading "Court proceedings" below applies."#),

        .sub("Court proceedings"),
        .body(#"Any dispute that is not subject to arbitration will be brought exclusively in the state or federal courts located in Morris County, New Jersey, and you and TAGS consent to personal jurisdiction and venue in those courts, except that either party may bring an eligible claim in small-claims court as described above."#),
        .caps(#"TO THE FULLEST EXTENT PERMITTED BY LAW, YOU AND TAGS EACH WAIVE THE RIGHT TO A TRIAL BY JURY IN ANY PROCEEDING ARISING OUT OF OR RELATING TO THESE TERMS OR THE SERVICE."#),

        .sub("Governing law"),
        .body(#"These Terms are governed by the laws of the State of New Jersey and, as to the arbitration agreement, by the Federal Arbitration Act, without regard to conflict-of-law principles. This choice of law does not deprive you of the protection of any mandatory consumer-protection law of the state in which you reside."#),

        .sub("Changes to this Section"),
        .body(#"If TAGS changes this Section after you accept these Terms, you may reject the change by sending the opt-out email described above within 30 days after the change takes effect. If you do so, the version of this Section that you most recently accepted will continue to govern disputes between you and TAGS."#),

        .heading("20. Changes to These Terms"),
        .body(#"We may update these Terms. We will post the revised Terms and update the effective date. For material changes, we will provide additional notice as required by law, and the Service will ask you to read and accept the updated Terms before you continue using it. If you continue using the Service after updated Terms become effective, you accept them, except where affirmative consent is legally required. Each edition of these Terms is identified by its effective date and by a document fingerprint displayed in the Legal section of the Service and on our website, so that you can identify the edition you accepted."#),

        .heading("21. General Terms"),
        .body(#"These Terms and the Privacy Policy are the entire agreement concerning the Service. If a provision is unenforceable, it will be modified to the minimum extent necessary or severed, and the remaining provisions will remain effective. Our failure to enforce a provision is not a waiver. You may not assign these Terms without our consent; we may assign them in connection with a reorganization, financing, merger, acquisition, or transfer of the Service. Section headings are for convenience only."#),
        .body(#"You consent to receive notices, disclosures, and other communications from TAGS electronically, by email to an address you have used to correspond with us or by posting within the Service, and you agree that electronic communications satisfy any legal requirement that a communication be in writing. Notices to TAGS must be sent to legal@playtagsnow.com unless another address is specified for a particular purpose in these Terms."#),
        .body(#"TAGS is not liable for any failure or delay in performance caused by circumstances beyond its reasonable control, including acts of God, natural disaster, epidemic, war, terrorism, civil unrest, labor dispute, governmental action, or failure of the internet, of telecommunications, or of services operated by Apple or another third party."#),
        .body(#"You agree to comply with all applicable export control and economic sanctions laws in connection with the Service, and you may not use or export the Service in violation of those laws. Except for Apple as provided in Section 22, these Terms confer no rights on any third party."#),

        .heading("22. Apple App Store Terms"),
        .body(#"If you obtain the Service through Apple's App Store, you acknowledge that these Terms are between you and TAGS, not Apple; Apple has no obligation to provide maintenance or support; Apple is not responsible for claims relating to the Service except as required by law; Apple and its subsidiaries are third-party beneficiaries of these Terms and may enforce them; and your use must comply with applicable App Store terms. You represent and warrant that you are not located in a country that is subject to a United States government embargo or that has been designated by the United States government as a "terrorist supporting" country, and that you are not listed on any United States government list of prohibited or restricted parties."#),

        .heading("23. Contact"),
        .contact("""
        TAGs Media LLC
        support@playtagsnow.com
        www.PlayTAGsNow.com
        """)
    ]
}
