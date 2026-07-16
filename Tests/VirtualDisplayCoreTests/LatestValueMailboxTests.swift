import Testing
@testable import VirtualDisplayCore

@Test func mailboxKeepsOnlyLatestPendingValue() {
    let mailbox = LatestValueMailbox<Int>()
    mailbox.activate()
    #expect(mailbox.offer(1))
    #expect(!mailbox.offer(2))
    #expect(mailbox.take() == 2)
    #expect(!mailbox.finishDrain())
}

@Test func mailboxSchedulesAgainWhenValueArrivesDuringDrain() {
    let mailbox = LatestValueMailbox<Int>()
    mailbox.activate()
    #expect(mailbox.offer(1))
    #expect(mailbox.take() == 1)
    #expect(!mailbox.offer(2))
    #expect(mailbox.finishDrain())
    #expect(mailbox.take() == 2)
    #expect(!mailbox.finishDrain())
}

@Test func mailboxDropsValuesWhileInactive() {
    let mailbox = LatestValueMailbox<Int>()
    #expect(!mailbox.offer(1))
    mailbox.activate()
    #expect(mailbox.offer(2))
    mailbox.deactivateAndClear()
    #expect(mailbox.take() == nil)
    #expect(!mailbox.offer(3))
}
