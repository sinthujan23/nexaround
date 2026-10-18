"""Version 1 of each legal document, written to the database on first read.

After that the admin panel (Admin > Legal) is the source of truth; editing this
file changes nothing for a database that already has a version. The client's
own wording is kept verbatim where they supplied it; the rest is drafted to sit
around it and must be reviewed by their lawyer.

Body format: "## " heading, "- " bullet, blank line between paragraphs.
"""

CUSTOMER_TITLE = "Experience Booking Terms"

CUSTOMER_HIGHLIGHTS = [
    "Pay the provider directly at the location, by cash or card where accepted.",
    "Cancel at least 72 hours before the start, or the booking price may be due.",
    "Your request is confirmed only when the provider confirms it.",
    "Run by an independent local provider. Nexaround connects you.",
]

CUSTOMER_BODY = """\
## About Nexaround

Nexaround acts as an online intermediary platform connecting customers with independent experience providers offering tours, activities, excursions, workshops, cultural experiences, adventure activities, and other travel-related experiences.

Nexaround facilitates the discovery and booking of experiences by providing a platform through which customers can explore available activities, review experience details, submit booking requests, and communicate with experience providers.

Unless otherwise stated in the applicable booking terms, the experience reservation constitutes a direct contractual relationship between the customer and the experience provider. Nexaround does not itself organize, operate, supervise, or deliver experiences offered by independent providers, unless expressly stated otherwise.

## Your request and your booking

- Sending a request through Nexaround does not by itself create a booking. A booking is confirmed only when the experience provider confirms it with you.
- The person who sends a request accepts these terms on behalf of everyone in their group, and is responsible for any children in the group.
- Prices are set by the experience provider, may change, and are confirmed by the provider.

## Payment

Customers must pay the experience provider directly at the experience location using cash or a credit card, where accepted by the provider. Customers should confirm the accepted payment methods with the provider before attending.

Unless stated otherwise, Nexaround does not take payment for experiences. Providers are responsible for handling payments, cancellations and refunds under the booking terms and applicable law.

## Cancellations

Customers must cancel their bookings at least 72 hours before the scheduled start time. Cancellations made less than 72 hours in advance, or failure to attend, obligate the customer to pay the applicable booking price, subject to the booking terms and applicable law.

To cancel, use My requests in the Nexaround app, which records the time you cancelled and tells the provider at once. You can also contact the experience provider directly; if you do, keep a record of your cancellation.

If the provider cancels the experience, the provider must inform the customer and arrange any applicable refund or rescheduling in accordance with the booking terms and applicable law.

## The provider's responsibilities

Experience providers are solely responsible for the accuracy of the information they publish, including experience descriptions, itineraries, prices, schedules, availability, inclusions, exclusions, eligibility requirements, and safety instructions. Providers are also responsible for obtaining all necessary permits, licences, insurance, and authorizations and for ensuring that their experiences are conducted safely and in compliance with applicable laws and regulations.

## Your responsibilities

Customers are responsible for reviewing the experience details, participation requirements, age restrictions, physical requirements, cancellation policies, and other applicable terms before making a booking. Customers must follow the instructions and safety guidance provided by the experience provider during the activity.

- You confirm that you and everyone in your group are fit and able to take part in the experience you request.
- Some experiences carry risks, especially adventure and water activities. You take part at your own risk, to the extent permitted by law.
- We strongly recommend suitable travel and health insurance.

## Your contact details

To handle your request, Nexaround shares your name, phone number, email address and request details with the experience provider. The provider may use them only to respond to and fulfil your request. Our Privacy Policy explains how Nexaround handles your information.

## Accuracy and concerns

Nexaround makes reasonable efforts to maintain accurate information on its platform but does not guarantee the quality, safety, legality, availability, or suitability of experiences offered by independent providers. Any concerns relating to the delivery of an experience should be reported to Nexaround and/or the relevant provider through the available support channels.

## Limitation of liability

To the fullest extent permitted by applicable law, Nexaround shall not be liable for losses, injuries, damages, cancellations or service failures arising from independent providers or their experiences.

If Nexaround is nevertheless found liable, its total liability for any booking is limited to the fees Nexaround received for that booking. Nothing in these terms excludes or limits any liability that cannot be excluded or limited by law.

## Our rights

Nexaround may decline or remove requests, and may suspend accounts, that breach these terms or misuse the platform.

Nexaround is not responsible for failures or delays caused by events beyond its reasonable control, such as severe weather, natural disasters, government action, or disruption to transport or communications.

## Changes to these terms

Nexaround may update these terms. When it does, the app shows the new version and asks you to accept it before your next request. Each request is governed by the version you accepted when you sent it.

## General

If any part of these terms is found to be unenforceable, the rest remains in effect.

Your booking with an experience provider is governed by the laws of the country where the experience takes place. These terms are governed by the laws of the United Arab Emirates, and any dispute with Nexaround will be handled by the courts of Dubai, United Arab Emirates, except where the law of the country you live in gives you rights that cannot be removed by agreement.

Before starting any legal claim, please contact Nexaround support first so we can try to resolve it. Most issues can be settled within 30 days.
"""

PROVIDER_TITLE = "Experience Provider Agreement"

PROVIDER_HIGHLIGHTS = [
    "You run the experience and are responsible for its safety, licences and insurance.",
    "Customers pay you directly; you handle cancellations and refunds.",
    "Customers may cancel up to 72 hours before the start without paying.",
    "Use customers' contact details only to handle their request.",
]

PROVIDER_BODY = """\
## About Nexaround

Nexaround acts as an online intermediary platform connecting customers with independent experience providers offering tours, activities, excursions, workshops, cultural experiences, adventure activities, and other travel-related experiences.

Unless otherwise stated in the applicable booking terms, the experience reservation constitutes a direct contractual relationship between the customer and the experience provider. Nexaround does not itself organize, operate, supervise, or deliver experiences offered by independent providers, unless expressly stated otherwise.

You and Nexaround are independent parties. Nothing in this agreement creates a partnership, joint venture, employment or agency relationship.

## Your listings

Experience providers are solely responsible for the accuracy of the information they publish, including experience descriptions, itineraries, prices, schedules, availability, inclusions, exclusions, eligibility requirements, and safety instructions.

- Keep your prices, availability and blocked dates up to date.
- Describe any risks, age limits, health or fitness requirements, and what customers must bring.

## Licences, insurance and safety

Providers are responsible for obtaining all necessary permits, licences, insurance, and authorizations and for ensuring that their experiences are conducted safely and in compliance with applicable laws and regulations.

- Hold public liability insurance suitable for your experiences, and provide proof to Nexaround on request.
- Use trained staff and properly maintained equipment, and give customers clear safety instructions.

## Requests and bookings

- Respond to customer requests promptly, and confirm or decline each one clearly.
- A booking is confirmed only when you confirm it with the customer. Mark it confirmed in the partner portal, with the agreed date, so the customer is notified and the cancellation rule can be applied.
- Customers can cancel in the Nexaround app. You are notified when they do, with the time they cancelled.

## Payments, cancellations and refunds

Unless stated otherwise, customers pay providers directly. Customers pay you at the experience location using cash or a credit card, where you accept it. Providers are responsible for delivering experiences and handling payments, cancellations and refunds under the booking terms and applicable law.

Customers may cancel at least 72 hours before the scheduled start time without paying. Cancellations made less than 72 hours in advance, or failure to attend, obligate the customer to pay the applicable booking price, subject to the booking terms and applicable law.

If you cancel an experience, you must inform the customer promptly and arrange any applicable refund or rescheduling in accordance with the booking terms and applicable law.

## Customer information

Nexaround shares customers' contact details with you only so that you can handle their request.

- Use them only to respond to and fulfil that request.
- Do not sell or share them, or use them for unrelated marketing.
- Keep them secure and comply with applicable data protection law.

## Indemnity

You agree to indemnify and hold harmless Nexaround, its operators, employees and agents against any claims, losses, damages, fines and costs (including reasonable legal fees) arising from your experiences, your listings, your breach of this agreement or of any law, or the acts or omissions of your staff.

## Limitation of liability

To the fullest extent permitted by applicable law, Nexaround shall not be liable for losses, injuries, damages, cancellations, service failures or lost business arising from your experiences or from your use of the platform. The platform is provided as it is, without a guarantee of uninterrupted availability.

If Nexaround is nevertheless found liable, its total liability is limited to the fees you paid Nexaround in the twelve months before the claim. Nothing in this agreement excludes or limits any liability that cannot be excluded or limited by law.

## Our rights

Nexaround may review, decline, hide or remove listings, and may suspend or close provider accounts, that breach this agreement, receive serious complaints, or put customers at risk.

## Accepting on behalf of your business

The person who accepts this agreement confirms that they are authorised to do so on behalf of the business named in the partner portal, and that the business is bound by it.

## Changes to this agreement

Nexaround may update this agreement. When it does, the partner portal shows the new version and asks you to accept it. If it is not accepted within 14 days, your experiences may be hidden from the app until it is.

## General

If any part of this agreement is found to be unenforceable, the rest remains in effect.

This agreement is governed by the laws of the United Arab Emirates, and any dispute between you and Nexaround will be handled by the courts of Dubai, United Arab Emirates. You must also comply with the laws of every country where you offer experiences.
"""
