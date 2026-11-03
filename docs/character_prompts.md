# Stock-Life 角色外观提示词

用于 AI 生成角色半身立绘。依据：GDD 第 3、9 节，`data/characters.json`（主角、诺艾尔、渡鸦夫人、米娅的配色），`data/companies.json`（看板娘主题色与头饰）。

- 维多利亚、卡尔、赛琳以及第 6–8 家公司的看板娘，在 GDD 里只有身份和性格，外观是按设定补写的，可以自由修改。
- 每个角色都给出中文和英文两版提示词，内容一致。多数图像模型对英文理解更稳定，建议优先使用英文版。
- 年龄：主角希雅 17 岁，其他女性角色也都写得年轻（多在 16–20 岁之间）；渡鸦夫人和赛琳因为身份需要，比其他人稍大一些。服装都是正常的工作服或日常服装。
- 颜值：主角走可爱风格；所有角色都是好看的长相，皮肤干净，不画雀斑、痣、伤疤、创可贴、脏污之类影响颜值的细节。

---

## 0. 通用风格（每条提示词前面都加上）

**中文**
> 2D 日系二次元角色立绘，清爽的赛璐璐上色，线条干净，色块分明，带柔和的高光与阴影。半身像，从腰部到头顶，身体微微侧向一边、脸朝向观众，双手可见。背景为纯白或透明，无任何文字和水印。整体世界观是“魔导蒸汽朋克”：服装上有黄铜扣件、齿轮纹样、镶嵌发光魔晶石的小饰品，主色调为金色与深蓝。角色五官精致好看，皮肤光洁干净，没有雀斑、痣、伤疤、痘痘、创可贴或脸上的脏污。

**English**
> 2D anime-style character portrait, clean cel shading, crisp lineart, flat color blocks with soft highlights and shadows. Half-body shot from the waist up, body turned slightly to one side, face toward the viewer, both hands visible. Plain white or transparent background, no text, no watermark. The world is "arcane steampunk": outfits feature brass buttons, subtle gear motifs and small accessories set with glowing magic crystals; overall palette leans on gold and deep blue. Beautiful, well-proportioned facial features and smooth, clear, flawless skin, with no freckles, moles, scars, acne, bandages or dirt on the face.

**负面提示词**（支持 negative prompt 的工具填这一栏）
> freckles, moles, beauty marks, scars, acne, pimples, skin blemishes, bandages, band-aids, dirt on face, smudges, wrinkles, eye bags, ugly, deformed face, asymmetrical eyes, extra fingers, bad hands, text, watermark, signature

主角“疲劳”状态需要画黑眼圈，生成那一张时把负面提示词里的 eye bags 去掉。

**保持一致性的做法**
1. 先用“基础提示词 + 平静/普通表情”生成满意的定稿图。
2. 之后用定稿图做参考图（图生图 / 角色参考 / 局部重绘），只改表情和道具，生成表情差分与状态差分。
3. 每次生成都保留同一句发色、瞳色、头饰描述，不要省略。

---

## 1. 主角 · 希雅（见习交易员）

识别点：蜂蜜金色头发 + 蓝色大蝴蝶结、水汪汪的大蓝眼睛、深蓝色交易员制服、金色纽扣。可爱风格：乡下来的小姑娘，单纯、元气、努力，有点小迷糊。

**中文**
> 一位 17 岁的可爱少女见习交易员，刚从乡下来到帝国首都，天真单纯、元气满满，神情认真又带着一点可爱的紧张。娇小的身材，柔软圆润的小脸，白里透粉的光洁肌肤，脸颊带着淡淡的自然红晕。一双又大又亮、水汪汪的天蓝色眼睛，眼中有星星般的高光，睫毛长而卷翘。蜂蜜金色的长发柔顺有光泽，发尾蓬松微卷，扎成低侧马尾，额前是轻盈的空气刘海，头顶系着一个深蓝色的大蝴蝶结发带，发带边缘有金色滚边，两条飘带垂在耳侧。穿着深海军蓝的交易员制服外套，袖子稍长、盖住一半手背，显得小巧可爱；金色双排扣，白色衬衫配深蓝色小领结，左胸别着一枚刻有交易所徽章的黄铜胸针。双手把一本皮面账本抱在胸前。整体干净清爽，甜美可爱。

**English**
> A cute 17-year-old girl, an apprentice stock trader who has just arrived in the imperial capital from the countryside; innocent, cheerful and full of energy, with an earnest expression and a hint of adorable nervousness. Petite build, soft round face, smooth fair skin with a natural rosy blush on her cheeks. Big, bright, sparkling sky-blue eyes with star-like highlights and long curled lashes. Long, glossy honey-blonde hair with fluffy, softly curled ends, tied in a low side ponytail, light wispy bangs, and a large navy-blue bow ribbon on top of her head with gold trim, its two tails hanging beside her ears. She wears a deep navy trader's coat with slightly long sleeves that half cover her hands, gold double-breasted buttons, a white shirt with a small navy bow tie, and a brass pin engraved with the stock exchange emblem on her left chest. She hugs a leather-bound ledger to her chest with both hands. Clean, fresh, sweet and adorable overall.

**状态差分**（GDD 第 9 节，基于定稿图追加以下描述）

负面状态也画成可爱的漫画式表现（汗滴、红晕、小黑眼圈这类符号），不要画得憔悴、难看。

| 状态 | 追加描述（中文） | 追加描述（English） |
|------|------------------|---------------------|
| 平静 | 甜甜的微笑，坐姿端正 | sweet gentle smile, sitting upright |
| 乐观 | 开心地眯眼笑，一只手在脸旁比 V 字 | happy closed-eye smile, making a V sign beside her face |
| 悲观 | 委屈地撇嘴、垂着眉毛低头，头顶飘着一小朵乌云 | pouting with drooping eyebrows, head lowered, a tiny cartoon rain cloud above her head |
| 狂热 | 大眼睛里闪着金币形状的高光，脸颊红扑扑，双手握拳举在胸前 | gold-coin-shaped sparkles in her big eyes, rosy cheeks, both fists raised in front of her chest |
| 恐慌 | 泪眼汪汪，额头挂着漫画式的大汗滴，双手抱头 | teary eyes, a big cartoon sweat drop on her forehead, hands on her head |
| 疲劳 | 眼睛半眯，眼下淡淡的漫画式黑眼圈，用手捂嘴打哈欠，一缕呆毛翘起 | sleepy half-closed eyes, faint cartoon-style shadows under her eyes, covering a yawn with her hand, a single strand of hair sticking up |
| 感冒 | 戴着小小的白色口罩，鼻尖微微泛红，裹着一条毛茸茸的毛毯 | small white face mask, the tip of her nose slightly pink, wrapped in a fluffy blanket |
| 发烧 | 脸颊通红，额头敷着冰袋，眼睛迷迷糊糊，头顶冒着小热气 | deeply flushed cheeks, ice pack on her forehead, dazed dreamy eyes, little cartoon steam puffs above her head |
| 住院 | 穿浅蓝色病号服，抱着枕头靠在白色病床上，神情乖巧 | light-blue hospital gown, hugging a pillow while leaning back on a white hospital bed, a meek, docile expression |

---

## 2. 诺艾尔（精灵族会计师 · 秘书）

识别点：淡薄荷银色长发、尖长精灵耳、细框眼镜、翠绿眼睛、墨绿色秘书套装。冷静毒舌，外冷内热。

**中文**
> 一位外表约 18 岁的精灵族少女，担任会计师兼秘书，气质冷静、干练，带一点毒舌的冷淡感。及背的淡薄荷银色直发，整齐地别在耳后，露出一对细长的尖精灵耳。翠绿色的眼睛，眼神锐利，戴一副香槟金色细框椭圆眼镜，镜链垂在脸侧。穿着修身的墨绿色秘书套装：高领白衬衫、深墨绿马甲和长外套，香槟金色纽扣，胸前口袋插着一支羽毛笔。一手托着一本厚厚的账簿，一手轻推眼镜。表情淡然，嘴角似笑非笑。

**English**
> An elven girl who looks about 18, working as an accountant and personal secretary; calm, sharp and composed, with a dry, cool aloofness. Straight, back-length pale mint-silver hair neatly tucked behind long pointed elf ears. Emerald-green eyes with a sharp gaze, wearing thin champagne-gold oval glasses with a chain hanging beside her face. She wears a tailored dark forest-green secretary suit: high-collared white blouse, deep green waistcoat and long coat with champagne-gold buttons, a quill pen tucked in her breast pocket. One hand holds a thick ledger, the other pushes up her glasses. Neutral expression with the faintest hint of a smirk.

**表情差分**（对话中用到的）：普通、微笑（难得的温柔笑）、不耐烦（半眯眼、叹气）、担忧（皱眉、手扶下巴）、惊讶（睁大眼、眼镜滑下鼻梁）。

---

## 3. 渡鸦夫人（黑鸦商会会长 · 债主）

识别点：近黑带紫调的长发、黑色面纱小礼帽、深红色眼睛、深紫红礼裙、黑羽毛装饰、古铜金饰品。优雅而危险。

**中文**
> 一位约 23 岁的年轻女性，黑鸦商会的会长，年纪轻轻却气场成熟，优雅、从容、带着危险的压迫感。乌黑中透着暗紫光泽的长卷发，盘起一半、其余垂在肩上。头戴一顶小巧的黑色礼帽，帽檐垂下一层黑色蕾丝面纱，半遮住眼睛，帽侧插着几根渡鸦黑羽。深红色的眼睛，眼尾上挑，涂着深色口红。穿着深紫红色的高领维多利亚式礼裙，肩部有黑色羽毛披肩，腰间和领口点缀古铜金色的乌鸦纹饰和一枚暗红色宝石胸针。戴黑色长手套，手里拿着一把合起的黑羽扇，掩在唇边，露出从容而意味深长的微笑。

**English**
> A young woman around 23, head of the Black Raven Trading Company; young but with a mature, commanding aura; elegant, unhurried, quietly dangerous. Long wavy black hair with a dark violet sheen, half pinned up with the rest falling over her shoulders. A small black hat with a black lace veil that half covers her eyes, a few raven-black feathers on its side. Deep crimson eyes with upturned corners, dark lipstick. She wears a deep plum, high-collared Victorian-style gown with a black feather shoulder cape, antique bronze raven ornaments at the collar and waist, and a dark red gemstone brooch. Long black gloves; she holds a closed black feather fan near her lips, with a composed, knowing smile.

**表情差分**：得意（smug，微抬下巴、眯眼）、微笑（smile，罕见的真心欣赏）、冷脸（不笑，眼神冰冷）、轻笑（以扇掩口）。

---

## 4. 米娅（《金穗日报》猫耳记者）

识别点：杏橙色短发、猫耳和猫尾、橄榄绿眼睛、棕色报童帽与马甲、手持记事本和魔导相机。活泼、八卦。

**中文**
> 一位约 17 岁的猫耳兽人少女，报社的见习记者，活泼好动、好奇心旺盛，一副随时要抢独家新闻的样子。杏橙色的蓬松短发，头顶一对同色毛茸茸的猫耳，一只耳朵从歪戴的棕色报童帽下钻出来，身后露出一条橙色猫尾。橄榄绿色的大眼睛，猫一样的竖瞳，嘴角露出一颗小虎牙。穿着奶油色衬衫、棕色背带马甲和及膝短裤，脖子上挂着一台镶有魔晶石镜头的黄铜魔导相机，耳后夹着铅笔，手里拿着翻开的记事本，帽子上插着一张写着“金穗日报”的记者证。身体前倾，像在凑近打听消息。

**English**
> A cat-eared beastfolk girl around 17, a junior newspaper reporter; lively, nosy, always chasing the next scoop. Fluffy short apricot-orange hair with matching furry cat ears, one ear poking out from under a tilted brown newsboy cap, an orange cat tail visible behind her. Big olive-green eyes with cat-like slit pupils, a small fang showing at the corner of her grin. She wears a cream shirt, a brown waistcoat with suspenders and knee-length shorts, a brass camera with a glowing crystal lens hanging around her neck, a pencil tucked behind her ear, and an open notepad in hand; a press pass is tucked into her cap band. Leaning forward as if eagerly fishing for gossip.

**表情差分**：兴奋（眼睛闪光、猫耳竖起）、八卦脸（掩嘴坏笑）、得意（拿着独家照片）、慌张（猫耳压平、尾巴炸毛）。

---

## 5. 维多利亚（格兰兹家族千金 · 基金经理）

识别点：铂金色大卷发、紫罗兰色眼睛、白金配色的贵族套装、单片眼镜或折扇。高傲的价值投资派。（外观为补写）

**中文**
> 一位约 18 岁的贵族千金，年纪轻轻就当上了基金经理，高傲、自信，举止讲究，带着居高临下的优雅。铂金色的长发，两侧做成华丽的螺旋大卷，发间别着一枚镶蓝宝石的家族徽章发夹。紫罗兰色的眼睛，眼神不屑。穿着白色与香槟金配色的贵族风西装长裙套装，肩部有金色肩章，领口系着深蓝色丝巾，胸前别着格兰兹家族的狮鹫纹章。一手叉腰，一手拿着一份装订精美的财报，下巴微微抬起。

**English**
> A noble heiress around 18 who already runs an investment fund; proud, confident and refined, with a condescending elegance. Long platinum-blonde hair styled into large ornate drill curls on both sides, a family crest hairpin set with a sapphire. Violet eyes with a dismissive look. She wears an aristocratic white and champagne-gold tailored suit with a long skirt, gold epaulettes, a deep navy silk cravat, and a griffin family crest brooch on her chest. One hand on her hip, the other holding a finely bound financial report, chin slightly raised.

---

## 6. 卡尔 · “疯狗”（下城投机客 · 散户领袖）

识别点：乱翘的红棕色短发、红色头巾和护目镜、敞开的旧皮夹克、一卷报纸、露齿大笑。热血、追涨杀跌。（外观为补写，性别按名字设为男性）

**中文**
> 一位约 24 岁的年轻男性，下城出身的投机客、散户们的带头大哥，热血冲动、嗓门很大。乱糟糟往上翘的红棕色短发，额头上绑着一条红色头巾，脖子上挂着一副旧黄铜护目镜。琥珀色的眼睛，五官英气，露出一口白牙的张扬大笑。穿着敞开的旧棕色皮夹克，里面是洗得发白的背心，挂着几串叮当响的铜币项链。一只手高举着卷起的报纸像在振臂高呼，另一只手竖起大拇指。

**English**
> A young man around 24, a speculator from the lower city and ringleader of the small retail traders; hot-blooded, impulsive and loud. Messy, spiky reddish-brown short hair, a red bandana tied around his forehead, old brass goggles hanging around his neck. Amber eyes, handsome sharp features, a wide toothy grin. He wears an open, worn brown leather jacket over a faded tank top, with jangling strings of copper coins as necklaces. One hand raises a rolled-up newspaper as if rallying a crowd, the other gives a thumbs-up.

---

## 7. 赛琳（金融监察厅监察官）

识别点：黑色齐肩短发、冷灰色眼睛、深蓝色制服大衣、银色徽章与天平纹章、手持文件夹。正直、固执。（外观为补写）

**中文**
> 一位约 20 岁的年轻女性金融监察官，监察厅史上最年轻的监察官，正直、严肃、一丝不苟，给人不讲情面的压迫感。利落的黑色齐肩短发，刘海整齐，一侧别着银色发夹。冷灰色的眼睛，目光笔直，表情严肃。穿着笔挺的深蓝色双排扣制服大衣，银色纽扣，高领，左胸佩戴刻有天平图案的银色监察厅徽章，腰间系着黑色皮带。戴白色手套，一手夹着一叠盖有红色印章的调查文件，一手出示徽章。

**English**
> A young female financial inspector around 20, the youngest inspector in the agency's history; upright, stern and meticulous, with an uncompromising presence. Neat black shoulder-length bob with tidy bangs, a silver hairclip on one side. Cool gray eyes, a direct, steady gaze, serious expression. She wears a crisp deep navy double-breasted uniform greatcoat with silver buttons and a high collar, a silver inspectorate badge engraved with a balance scale on her left chest, and a black leather belt. White gloves; one hand holds a stack of investigation files stamped in red, the other presents her badge.

---

## 8. 上市公司看板娘

看板娘是公司的拟人化形象，主题色取自公司的行情色，头饰与 `characters.json` 中的 `mascot_features` 对应。表情差分统一为：狂喜、开心、普通、担忧、哭泣、崩溃（GDD 第 9 节），可在定稿图上追加：

| 表情 | 中文 | English |
|------|------|---------|
| 狂喜 | 双手高举欢呼，眼睛闪光，背后金色光芒 | cheering with both arms raised, sparkling eyes, golden light behind her |
| 开心 | 灿烂的笑容 | big cheerful smile |
| 普通 | 自然的微笑 | relaxed natural smile |
| 担忧 | 皱眉，额角冒汗 | worried frown, a bead of sweat on her temple |
| 哭泣 | 眼泪汪汪，咬着嘴唇 | teary eyes, biting her lip |
| 崩溃 | 灵魂出窍般呆滞，整体颜色发灰 | blank, soul-leaving-body stare, desaturated gray tones |

### 8.1 艾尔 · 艾尔德魔导工坊（元气工程师）

**中文**
> 一位约 16 岁的元气少女工程师，活力满满。琥珀橙色的短马尾，额头上推着一副黄铜护目镜，镜片泛着魔晶石的蓝光。明亮的橙色大眼睛。穿着琥珀橙色的连体工装，上半身袖子系在腰间，里面是黑色短袖 T 恤，腰带上挂满扳手和螺丝刀，一只手戴着厚皮手套，扛着一把大号黄铜扳手。笑容灿烂。

**English**
> An energetic engineer girl around 16. Short amber-orange ponytail, brass goggles pushed up on her forehead with lenses glowing crystal blue. Bright, big orange eyes. She wears amber-orange coveralls with the top half tied around her waist over a black short-sleeved T-shirt, a tool belt full of wrenches and screwdrivers, one thick leather glove, and a big brass wrench resting on her shoulder. Beaming smile.

### 8.2 琳德 · 龙脊运输（龙人少女）

**中文**
> 一位约 17 岁的龙人族少女，飞龙物流公司的看板娘，开朗爽快。天蓝色的长发扎成高马尾，头顶两侧长着一对向后弯曲的深蓝色龙角，耳后和颈侧点缀着几片细小、闪亮的蓝色鳞片，身后露出一条带鳞的龙尾。金色竖瞳。穿着天蓝色与白色的飞行员外套，毛领，戴着皮质飞行手套，斜挎一个印有龙脊运输标志的邮包，手里拿着一张货运单。

**English**
> A dragonkin girl around 17, mascot of a wyvern logistics company; cheerful and straightforward. Long sky-blue hair in a high ponytail, a pair of backward-curving dark blue dragon horns, a few small, shiny blue scales behind her ears and along the side of her neck, and a scaled dragon tail behind her. Golden slit-pupil eyes. She wears a sky-blue and white aviator jacket with a fur collar, leather flight gloves, a courier satchel bearing the company logo across her body, and holds a cargo slip.

### 8.3 塞拉 · 晨星药剂（安静的炼金术士）

**中文**
> 一位约 17 岁的安静内向的少女炼金术士。淡紫色的长直发，戴一顶宽檐的深紫色尖顶魔女帽，帽檐挂着一枚星形吊坠。浅紫色的眼睛，眼神温柔、有点困倦。穿着薰衣草紫色的长袍，外罩白色实验围裙，腰间挂着几个装有彩色药水的小玻璃瓶，双手捧着一只冒着淡淡星光的烧瓶。表情平静，略带羞涩。

**English**
> A quiet, introverted alchemist girl around 17. Long straight pale lavender hair under a wide-brimmed dark purple pointed witch hat with a small star charm hanging from the brim. Light violet eyes, gentle and slightly sleepy. She wears a lavender robe under a white lab apron, several small vials of colorful potions hanging from her belt, and holds a flask that gives off a faint starry glow in both hands. Calm, slightly shy expression.

### 8.4 小麦 · 金麦商社（乡下大姐）

**中文**
> 一位约 20 岁的乡下大姐姐，热情、豪爽、会照顾人。麦黄色的长发编成一条粗麻花辫搭在肩上，头上包着一块白底麦穗图案的头巾。温暖的棕色眼睛，健康红润的好气色。穿着麦黄色的农家连衣裙，挽起袖子，系着白色围裙，怀里抱着一大捆金色麦穗，另一只手叉腰，笑得爽朗。

**English**
> A warm, big-sisterly country girl around 20; friendly, hearty and caring. Long wheat-blonde hair in a thick braid over one shoulder, a white headscarf with a wheat-ear pattern. Warm brown eyes, a healthy, glowing complexion. She wears a wheat-yellow farm dress with rolled-up sleeves and a white apron, holding a large bundle of golden wheat in one arm, the other hand on her hip, laughing heartily.

### 8.5 莉莉 · 冒险者公会联合（新人冒险者）

**中文**
> 一位约 16 岁的新人少女冒险者，冒失、热血、跃跃欲试。珊瑚红色的短发，额头绑着一条红色布头带，带尾在脑后飘动。红色的眼睛，充满干劲。穿着珊瑚红色束腰外衣和皮革护胸、短披风，前臂戴着皮革护腕，腰间挂着一把略显崭新的短剑和一块铜色的新手冒险者徽章，手里举着一张委托单。

**English**
> A rookie adventurer girl around 16; reckless, fired up and eager. Short coral-red hair with a red cloth headband whose tails flutter behind her head. Red eyes full of determination. She wears a coral-red tunic with a leather chest guard and a short cape, leather bracers on her forearms, a shiny new short sword and a copper novice adventurer badge at her belt, holding up a quest notice.

### 8.6 之后的看板娘（MVP 未实装，外观为补写）

**克丽丝 · 水晶矿业（矿工头领）**
> 中文：一位约 19 岁、身材结实的少女矿工头领，粗犷可靠。深灰色短发，头戴装有发光魔晶石矿灯的黄铜安全帽。青蓝色的眼睛，五官清秀。穿着耐磨的帆布工作服，袖子挽起，肩上扛着一把镐头，腰间挂着一块发光的淡蓝色魔晶石原石。
>
> English: A sturdy, reliable girl around 19 who leads a mining crew. Short dark gray hair, a brass hard hat fitted with a glowing crystal lamp. Cyan-blue eyes, pretty, delicate features. She wears rugged canvas workwear with rolled-up sleeves, a pickaxe over her shoulder, and a raw pale blue glowing crystal hanging at her belt.

**艾莉诺 · 帝国皇家银行（端庄行长千金）**
> 中文：一位约 18 岁的端庄少女，银行行长的千金，温柔得体。深蓝色长发盘成优雅的低发髻，别着金色发簪。蓝色的眼睛，神情温和。穿着深蓝色与金色的高雅长裙，白色蕾丝领，胸前别着一枚金币形状的胸针，双手交叠捧着一本皮面存折。
>
> English: A graceful, well-mannered young lady around 18, daughter of the royal bank's governor. Long deep navy hair in an elegant low bun with a gold hairpin. Gentle blue eyes. She wears an elegant deep navy and gold gown with a white lace collar and a gold-coin-shaped brooch, hands folded holding a leather-bound bankbook.

**露露 · 幻灯歌剧院（当红歌姬）**
> 中文：一位约 17 岁的当红少女歌姬，闪亮、张扬、爱出风头。粉色的双马尾，发尾渐变为金色，头戴小巧的星形发饰。粉红色的眼睛，眼角点着亮片。穿着粉色与白色的舞台演出服，层叠荷叶边及膝裙，手持一支镶魔晶石的黄铜复古麦克风，俏皮地眨眼。
>
> English: A popular idol singer girl around 17; sparkly, flamboyant and attention-loving. Pink twin tails fading to gold at the tips, a small star-shaped hair ornament. Pink eyes with glitter at the corners. She wears a pink and white stage costume with a knee-length layered ruffled skirt, holding a vintage brass microphone set with a magic crystal, giving a playful wink.
