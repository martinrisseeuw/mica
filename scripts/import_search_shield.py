#!/usr/bin/env python3
"""Import the curated rule data from an explicitly supplied Search checkout."""
import json, pathlib, re, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]
source = pathlib.Path(sys.argv[1])
shield = (source / 'Sources/Search/Shield.swift').read_text()
youtube = (source / 'Sources/Search/YouTubeAds.swift').read_text()
def strings(text):
    return [json.loads(s) for s in re.findall(r'"(?:[^"\\]|\\.)*"', re.sub(r'//[^\n]*', '', text))]
def array(text, name):
    return strings(re.search(r'static let '+name+r'\s*=\s*\[(.*?)\n    \]', text, re.S)[1])
site_block = re.search(r'slotsBySite:.*?=\s*\[(.*?)\n    \]', shield, re.S)[1]
by_site = [{'hosts': [h.lstrip('*') for h in strings(hosts)], 'selector': json.loads(selector)}
           for hosts, selector in re.findall(r'\(\[(.*?)\],\s*("(?:[^"\\]|\\.)*")\)', site_block)]
by_site.append({'hosts':['reddit.com'], 'selector':', '.join(array(shield, 'reddit'))})
data = {'source':'https://github.com/driceroland/Search',
        'revision':subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip(),
        'domains':array(shield, 'unwanted'), 'selectors':array(shield, 'slots'),
        'siteSelectors':by_site, 'youtubePaths':array(youtube,'paths')}
(root/'resources/shield-rules.json').write_text(json.dumps(data,indent=2)+'\n')
(root/'resources/LICENSE-Search.txt').write_bytes((source/'LICENSE').read_bytes())
print(f"Imported {len(data['domains'])} domains and {len(data['selectors'])} generic cosmetic rules.")
