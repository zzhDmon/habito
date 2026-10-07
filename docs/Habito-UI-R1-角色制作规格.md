# Habito 角色制作规格 v0.1

> UI-R1-002A，候选Character Bible。主形象由002B母版与真实页面样稿共同验证；尚未代表用户对具体品种/配饰的正式确认。

## 固定候选

一只原创奶油色小狗，面向小学生的日系漫画伙伴；温暖、勇敢、略带顽皮，不像幼儿玩偶。不模仿现有动漫IP，不限定为真实品种。

- 轮廓：约2.5头身；圆润躯干配短但可辨的四肢，头约总高40%；耳朵为软三角下垂耳，不能变为直立柴犬耳。
- 颜色：奶油身躯、浅焦糖耳朵，口鼻与胸口更浅；深墨轮廓、黑褐小鼻。色块平涂，一层克制阴影，不用3D、毛发写实或水彩晕染。
- 脸部：两只小而有神的深色椭圆眼，不能变成占半张脸的玻璃大眼；嘴角可微笑。眉/汗滴等可做状态装饰，但不改变头型。
- 身份锚点：琥珀黄项圈、无字圆形吊牌、短而上弯的奶油尾巴。项圈颜色、耳朵轮廓、胸口色块与尾巴保持一致。
- 描边：手绘漫画墨线略有粗细变化，边缘清楚，不能全轮廓随机锯齿；与UI约2～3 pt的视觉重量协调。
- 情绪：默认期待、开心、鼓励、庆祝为首批；吃饭/升级随真实功能增加。困、饥饿、低心情不是已确认业务状态，不在首页按未做任务惩罚孩子。

## 母版和资源边界

002B先制作一张正面/四分之三/侧面的一致角色设定页，以及一个可放进三类样稿的透明默认姿态。设定页可有简单英文视角标注；正式UI文字保留原生可编辑文本。后续姿态必须以母版图作为视觉参考，不仅复用文字提示词。

透明图像保留alpha，四周留安全区，不截耳朵、尾巴或脚；阴影若需要由UI绘制，避免透明素材里烘焙大块地面。画布尺寸、导出密度和Asset Catalog配置在接入卡按实际显示尺寸确定。不得将图片生成的中文或假按钮当作实际操作。

## 生成提示词母版（002B使用内置image_gen）

Use case: illustration-story.
Asset type: character reference sheet for Habito, a Japanese manga growth adventure iPad app for primary-school children.
Primary request: an original cream-colored dog companion with three consistent full-body views: front, three-quarter, side. About 2.5 heads tall, soft triangular floppy caramel ears, cream body, pale muzzle and chest, small lively dark oval eyes, dark small nose, amber-yellow collar with a blank round tag, short upward-curving tail.
Style: expressive hand-inked Japanese manga, confident varying dark-brown linework, clean flat warm colors, one restrained cel-shadow; cute but not babyish, never an existing anime character.
Composition: spacious warm ivory reference sheet, same proportions and identity in every view, entire ears/tail/paws visible, minimal small English view labels only. No UI, no levels, no coins, no extra characters, no watermark.

透明默认姿态沿母版图编辑：保留所有身份锚点，只取四分之三站姿，朝向内容区、期待微笑，真实透明背景，无文字/地面/额外物品。实际执行提示词和工具方式须随产物记录。

## 检查清单

同一只狗、四肢合理、耳朵/项圈/尾巴一致；小尺寸仍能辨认；透明边缘无白框；三类样稿不换角色；普通/减少动态均能静态表达陪伴。样稿确认后才生产正式多状态资产。
