#!/usr/bin/env python3
"""Build assets/data/themes.json from the curated COCA theme files.

Source: tool/coca_theme/NN_<名称>.txt, one file per theme, in COCA order:

    == 通用（功能词与常用副词）（786 词）==
    1	the	（定冠词）这/那
    2	be	是

The rank column is the word's place in coca-20000.txt; the files partition the
vocabulary (no word sits in two themes), so the scene counts add up to the
number of curated words.

Each theme becomes one scene with a single group. The app's ThemeScene model
still carries groups because the JSON contract predates this flat taxonomy, and
a single group is what a flat list is.

The third column of each row is the word's Chinese gloss; it travels with the
group as `glosses` (word -> 释义) because the 背词 window shows the two side by
side and a parallel list would fall out of step with any filtered view.

A gloss ending in `*`, `**` or `***` marks the word as one to drill harder: the
stars are counted, stripped from the text, and written to
`assets/seed/vocab_stars.json`, which the 背词 window merges once per version.
"""

import argparse
import glob
import json
import os
import re

SRC = os.path.join('tool', 'coca_theme')
OUT = os.path.join('assets', 'data', 'themes.json')
STARS_OUT = os.path.join('assets', 'seed', 'vocab_stars.json')
COCA = 'coca-20000.txt'

HEADER = re.compile(r'^==\s*(?P<label>.+?)（(?P<count>\d+)\s*词）==$')
ROW = re.compile(r'^(?P<rank>\d+)\t(?P<word>[^\t]+)(?:\t(?P<gloss>.*))?$')
FILE = re.compile(r'^(?P<number>\d{2})_(?P<name>.+)\.txt$')

# Concise Chinese descriptions shown under each theme card in the UI.
HINTS = {
    '01': '代词、冠词、介词、连词与助动词',
    '02': '通用副词、逻辑衔接与口语感叹',
    '03': '物理属性、结构状态与松紧稳定',
    '04': '好坏优劣、真伪对错与重要程度',
    '05': '可能性、确定性、难易与常见度',
    '06': '异同、因果、关联与对比关系',
    '07': '事件、境况、机遇、风险与难题',
    '08': '一般抽象名词、类别模式与原则',
    '09': '行走奔跑、起坐站立与身体位移',
    '10': '拿放推拉、抓握切割与物理操控',
    '11': '起止持续、增减扩缩与演变过程',
    '12': '日常执行、尝试准备与习惯歇息',
    '13': '帮助支持、礼节交往与人际互动',
    '14': '男女老少、通用人称与亲友称谓',
    '15': '各行业职位、管理者与专业人士',
    '16': '社会身份、角色与人群评价标签',
    '17': '说话提问、辩论劝说与人声表达',
    '18': '词汇语法、书写翻译与书籍出版',
    '19': '新闻报刊、广电宣传与信息传播',
    '20': '知晓思考、记忆推理与智力活动',
    '21': '视听嗅触感知、观察与专注状态',
    '22': '喜爱希望、快乐满足与积极意愿',
    '23': '愤怒恐惧、悲伤焦虑与心理压力',
    '24': '性格特质、道德品行与精神态度',
    '25': '生活杂物、箱袋容器与文具小件',
    '26': '手工工具、工程机械与测量仪器',
    '27': '天然合成材料、金属矿产与化工',
    '28': '身体部位、器官骨骼与生理现象',
    '29': '疾病症状、药品疗法与医护保健',
    '30': '食材餐食、果蔬饮品与烹饪口感',
    '31': '亲属婚恋、室内房间与家居生活',
    '32': '衣服鞋帽、时尚配饰与美容仪容',
    '33': '颜色明暗、形状质感与声光气味',
    '34': '就业职场、企业组织与行政管理',
    '35': '货币交易、金融投资、市场消费',
    '36': '物理化学生物与自然科学研究',
    '37': '电脑软件、互联网通信与数码',
    '38': '社会群体、公共事务与风俗生活',
    '39': '政府体制、政党选举与国际外交',
    '40': '法律法规、法庭诉讼与治安犯罪',
    '41': '战争战役、军队武器与防卫和平',
    '42': '学校课程、考试学位与学术教学',
    '43': '美术音乐、戏剧影视与休闲娱乐',
    '44': '球类田径、健身锻炼与赛事竞技',
    '45': '宗教信仰、教会仪式与神话哲学',
    '46': '历史朝代、古代遗址与文明时代',
    '47': '各国民族、国籍族群与语言区域',
    '48': '房屋建筑、城乡街区与公共场馆',
    '49': '车船飞机、公路铁路与旅行出行',
    '50': '年月日时、四季周期与先后频次',
    '51': '数字序数、多少尺寸与度量数学',
    '52': '上下左右、东西南北与空间方位',
    '53': '风雨雷电、冷暖气候与自然环保',
    '54': '山川湖海、平原沙漠与地质地貌',
    '55': '花草树木、农林作物与园艺种植',
    '56': '鸟兽鱼虫、宠畜器官与动物习性',
    '57': '日月星辰、行星星系与航天探索',
}


def parse_file(path):
    """Returns (number, name, hint, words, glosses) for one theme file."""
    match = FILE.match(os.path.basename(path))
    if not match:
        raise SystemExit(f'{path}: not a NN_<名称>.txt file')
    number, name = match.group('number'), match.group('name')
    words = []
    glosses = {}
    star_counts = {}
    seen = set()
    for line in open(path, encoding='utf-8-sig'):
        line = line.strip().lstrip('\ufeff')
        if not line or line.startswith('=='):
            continue
        row = ROW.match(line)
        if not row:
            raise SystemExit(f'{path}: unreadable row: {line!r}')
        word = row.group('word').strip().lower()
        if word in seen:
            continue
        seen.add(word)
        words.append(word)
        gloss = (row.group('gloss') or '').strip()
        # `*` / `**` / `***` after the meaning is the star rating, not text.
        stars = 0
        while gloss.endswith('*'):
            stars += 1
            gloss = gloss[:-1].rstrip()
        if stars:
            star_counts[word] = stars
        if gloss:
            glosses[word] = gloss
    if not words:
        raise SystemExit(f'{path}: no words')
    return number, name, HINTS.get(number, ''), words, glosses, star_counts


def normalize(word):
    """COCA's file writes a few contractions with a doubled apostrophe
    (`n''t`, `o''clock`); the theme files spell them properly."""
    return word.replace("''", "'")


def coca_ranks():
    ranks = {}
    for index, line in enumerate(open(COCA, encoding='utf-8')):
        word = normalize(line.strip().lower())
        if word and word not in ranks:
            ranks[word] = index + 1
    return ranks


def build(src):
    paths = [path for path in sorted(glob.glob(os.path.join(src, '[0-9][0-9]_*.txt')))
             if not os.path.basename(path).startswith('00_')]  # 00_索引 lists the set
    if not paths:
        raise SystemExit(f'{src}: no theme files')
    ranks = coca_ranks()

    scenes = []
    placed = set()
    star_seed = {}
    for path in paths:
        number, name, hint, words, glosses, stars = parse_file(path)
        star_seed.update(stars)
        unknown = [w for w in words if w not in ranks]
        if unknown:
            raise SystemExit(f'{path}: not in {COCA}: {unknown[:5]}')
        # The files are meant to be in frequency order; a reshuffled file would
        # silently change what the first page shows.
        order = [ranks[w] for w in words]
        if order != sorted(order):
            raise SystemExit(f'{path}: words are not in COCA order')
        overlap = placed.intersection(words)
        if overlap:
            raise SystemExit(f'{path}: already placed elsewhere: {sorted(overlap)[:5]}')
        placed.update(words)
        scenes.append({
            'id': f't{number}',
            'label': name,
            'hint': hint,
            'count': len(words),
            'groups': [
                {'id': 'all', 'label': name, 'words': words, 'glosses': glosses}
            ],
        })

    return {
        'version': 2,
        'source': f'COCA 20000 · {len(scenes)} 个主题 · {len(placed)} 词',
        'scenes': scenes,
    }, star_seed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--src', default=SRC)
    parser.add_argument('--out', default=OUT)
    args = parser.parse_args()

    data, stars = build(args.src)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, 'w', encoding='utf-8') as handle:
        json.dump(data, handle, ensure_ascii=False, separators=(',', ':'))

    # The star seed bumps its version only when the ratings changed, so the app
    # merges it once and later reader changes to a star survive.
    version = 1
    if os.path.exists(STARS_OUT):
        try:
            with open(STARS_OUT, encoding='utf-8') as handle:
                old = json.load(handle)
            version = int(old.get('version', 1))
            if old.get('stars') == stars:
                version -= 1  # unchanged: keep the version we had
        except (OSError, ValueError):
            pass
    version += 1
    os.makedirs(os.path.dirname(STARS_OUT), exist_ok=True)
    with open(STARS_OUT, 'w', encoding='utf-8') as handle:
        json.dump({'version': version, 'stars': stars}, handle,
                  ensure_ascii=False, indent=0, sort_keys=True)

    total = sum(scene['count'] for scene in data['scenes'])
    size = os.path.getsize(args.out) / 1024
    print(f'{args.out}: {len(data["scenes"])} scenes, {total} words, '
          f'{size:.0f} KB')
    print(f'{STARS_OUT}: {len(stars)} starred words, version {version}')


if __name__ == '__main__':
    main()
