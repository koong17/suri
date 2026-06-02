import Foundation
import Testing
@testable import Suri

struct SlackDirectMessageTaskGrouperTests {
    @Test
    func groupsDirectMessagesByOwner() {
        let first = slackTask(
            title: "배포 일정 확인 부탁드려요",
            owner: "민수",
            dueDate: Date(timeIntervalSince1970: 2_000),
            priority: .normal,
            link: "https://slack.example.com/first"
        )
        let second = slackTask(
            title: "오늘 안에 답변 가능할까요?",
            owner: "민수",
            dueDate: Date(timeIntervalSince1970: 1_000),
            priority: .high,
            link: "https://slack.example.com/second"
        )
        let other = slackTask(
            title: "회의실 변경됐어요",
            owner: "지연",
            dueDate: nil,
            priority: .normal,
            link: "https://slack.example.com/other"
        )

        let grouped = SlackDirectMessageTaskGrouper().grouped([first, second, other])

        #expect(grouped.count == 2)
        let minsuGroup = grouped.first { $0.owner == "민수" }
        #expect(minsuGroup?.title.contains("민수 DM 2건") == true)
        #expect(minsuGroup?.priority == .high)
        #expect(minsuGroup?.metadata.first { $0.label == "메시지" }?.value == "2건")
        #expect(minsuGroup?.metadata.first { $0.label == "대화" }?.value == "slack-dm:민수")
    }

    @Test
    func leavesNonDirectSlackTasksUngrouped() {
        let mention = AssistantTask(
            title: "채널 공지",
            source: .slack,
            dueDate: nil,
            priority: .normal,
            status: .open,
            context: "@channel 확인 부탁드립니다.",
            owner: "Slack",
            requiresUserReview: true,
            recommendedAction: "확인",
            metadata: [
                MetadataItem(label: "채널", value: "general"),
                MetadataItem(label: "분류", value: "@here/@channel"),
                MetadataItem(label: "링크", value: "https://slack.example.com/channel")
            ]
        )

        let grouped = SlackDirectMessageTaskGrouper().grouped([mention])

        #expect(grouped == [mention])
    }

    private func slackTask(
        title: String,
        owner: String,
        dueDate: Date?,
        priority: TaskPriority,
        link: String
    ) -> AssistantTask {
        AssistantTask(
            title: title,
            source: .slack,
            dueDate: dueDate,
            priority: priority,
            status: .open,
            context: title,
            owner: owner,
            requiresUserReview: true,
            recommendedAction: "확인",
            metadata: [
                MetadataItem(label: "채널", value: "DM"),
                MetadataItem(label: "분류", value: "DM"),
                MetadataItem(label: "링크", value: link)
            ]
        )
    }
}
