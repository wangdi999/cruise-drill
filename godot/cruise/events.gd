extends Node

# 活动模式只需要上游 Card 和 CharacterStats 使用的两个事件。
signal card_played(card: Card)
signal player_hit
