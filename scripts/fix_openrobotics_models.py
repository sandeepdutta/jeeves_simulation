#!/usr/bin/env python3
"""
fix_openrobotics_models.py
Run this script after downloading/re-downloading models into ~/openrobotics.

What it does for every model directory found:
  1. Strips COLLADA FFP material references → creates <mesh>_clean.dae
  2. Updates model.sdf to reference _clean.dae
  3. Replaces <pbr> blocks with <ambient>/<diffuse>/<emissive>
  4. Removes <inertial> blocks (cause invalid inertia errors in Harmonic)
  5. Removes <meta> tags (break SDF parsing)

Usage:
    python3 ~/jeeves_simulation/scripts/fix_openrobotics_models.py
"""

import os
import re
import xml.etree.ElementTree as ET

MODELS_DIR = os.path.expanduser('~/openrobotics')
COLLADA_NS = 'http://www.collada.org/2005/11/COLLADASchema'

# Default material to substitute when PBR is removed.
# Per-model overrides: add an entry keyed by model dir name.
MODEL_COLORS = {
    'Refrigerator':  ('0.6 0.78 0.9 1',   '0.6 0.78 0.9 1',   '0.3 0.4 0.5 1', '0.03 0.04 0.05 1'),
    'Oven':          ('0.75 0.75 0.75 1',  '0.75 0.75 0.75 1', '0.5 0.5 0.5 1', '0.04 0.04 0.04 1'),
    'Armchair':      ('0.55 0.38 0.22 1',  '0.55 0.38 0.22 1', '0.2 0.15 0.1 1', '0.03 0.02 0.01 1'),
    'DiningChair':   ('0.71 0.52 0.32 1',  '0.71 0.52 0.32 1', '0.25 0.18 0.1 1', '0.04 0.03 0.02 1'),
    'DiningTable':   ('0.71 0.52 0.32 1',  '0.71 0.52 0.32 1', '0.25 0.18 0.1 1', '0.04 0.03 0.02 1'),
    'Piano':         ('0.08 0.08 0.08 1',  '0.08 0.08 0.08 1', '0.6 0.6 0.6 1',  '0.05 0.05 0.05 1'),
    '_default':      ('0.7 0.7 0.7 1',     '0.7 0.7 0.7 1',    '0.3 0.3 0.3 1', '0.04 0.04 0.04 1'),
}

# For visuals that already have a specific low diffuse (e.g. DiningTable Black legs),
# preserve their diffuse but ensure ambient/emissive are set.
BLACK_VISUAL_NAMES = {'visual_black', 'visual_metal'}


def clean_dae(src_path, out_path):
    ET.register_namespace('', COLLADA_NS)
    try:
        tree = ET.parse(src_path)
    except ET.ParseError as e:
        print(f'  PARSE ERROR {src_path}: {e}')
        return False
    root = tree.getroot()
    for tag in ['triangles', 'polylist', 'polygons', 'lines']:
        for elem in root.iter(f'{{{COLLADA_NS}}}{tag}'):
            elem.attrib.pop('material', None)
    for node in root.iter(f'{{{COLLADA_NS}}}instance_geometry'):
        for bm in list(node.findall(f'{{{COLLADA_NS}}}bind_material')):
            node.remove(bm)
    tree.write(out_path, xml_declaration=True, encoding='utf-8')
    return True


def build_material_xml(ambient, diffuse, specular, emissive, indent='          '):
    return (
        f'\n{indent}<ambient>{ambient}</ambient>'
        f'\n{indent}<diffuse>{diffuse}</diffuse>'
        f'\n{indent}<specular>{specular}</specular>'
        f'\n{indent}<emissive>{emissive}</emissive>'
    )


def fix_sdf(sdf_path, model_name):
    content = open(sdf_path).read()
    original = content

    # 1. Point mesh URIs to _clean.dae (avoid double-suffixing)
    def replace_dae(m):
        path = m.group(1)
        if '_clean' in path:
            return m.group(0)
        return path + '_clean.dae'
    content = re.sub(r'(meshes/[^"<\s]+?)\.dae', replace_dae, content)

    # 2. Remove <pbr>...</pbr> blocks
    content = re.sub(r'\s*<pbr>.*?</pbr>', '', content, flags=re.DOTALL)

    # 3. Remove <inertial>...</inertial> blocks
    content = re.sub(r'\s*<inertial>.*?</inertial>', '', content, flags=re.DOTALL)

    # 4. Remove <meta>...</meta> tags
    content = re.sub(r'\s*<meta>.*?</meta>', '', content, flags=re.DOTALL)

    # 5. Fix <material> blocks — ensure ambient/emissive present, replace bare diffuse+specular
    colors = MODEL_COLORS.get(model_name, MODEL_COLORS['_default'])
    ambient, diffuse, specular, emissive = colors

    def fix_material(m):
        mat = m.group(1)
        # Dark visuals (table legs, metal parts) — preserve low diffuse, patch missing tags
        if re.search(r'<diffuse>\s*0\.[0-3]', mat):
            for tag, val in [('ambient', '0.1 0.1 0.1 1'), ('emissive', '0.01 0.01 0.01 1')]:
                mat = re.sub(rf'<{tag}>[^<]*</{tag}>', f'<{tag}>{val}</{tag}>', mat)
                if f'<{tag}>' not in mat:
                    mat = mat.rstrip() + f'\n          <{tag}>{val}</{tag}>\n        '
            return f'<material>{mat}</material>'
        # Always replace colour tags with MODEL_COLORS values
        replacements = {
            'ambient':  ambient,
            'diffuse':  diffuse,
            'specular': specular,
            'emissive': emissive,
        }
        for tag, val in replacements.items():
            mat = re.sub(rf'<{tag}>[^<]*</{tag}>', f'<{tag}>{val}</{tag}>', mat)
        # Add any missing tags
        if '<ambient>' not in mat:
            mat = f'{build_material_xml(ambient, diffuse, specular, emissive)}\n        '
        return f'<material>{mat}</material>'

    content = re.sub(r'<material>(.*?)</material>', fix_material, content, flags=re.DOTALL)

    if content != original:
        open(sdf_path, 'w').write(content)
        return True
    return False


def main():
    if not os.path.isdir(MODELS_DIR):
        print(f'Directory not found: {MODELS_DIR}')
        return

    models = sorted(os.listdir(MODELS_DIR))
    print(f'Found {len(models)} entries in {MODELS_DIR}\n')

    for model_name in models:
        model_dir = os.path.join(MODELS_DIR, model_name)
        if not os.path.isdir(model_dir):
            continue

        dae_cleaned = 0
        meshes_dir = os.path.join(model_dir, 'meshes')
        if os.path.isdir(meshes_dir):
            for fname in os.listdir(meshes_dir):
                if not fname.lower().endswith('.dae') or '_clean' in fname:
                    continue
                src = os.path.join(meshes_dir, fname)
                out = os.path.join(meshes_dir, fname.replace('.dae', '_clean.dae').replace('.DAE', '_clean.DAE'))
                if clean_dae(src, out):
                    dae_cleaned += 1

        sdf_path = os.path.join(model_dir, 'model.sdf')
        sdf_updated = False
        if os.path.exists(sdf_path):
            sdf_updated = fix_sdf(sdf_path, model_name)

        status = []
        if dae_cleaned:
            status.append(f'{dae_cleaned} DAE cleaned')
        if sdf_updated:
            status.append('SDF updated')
        if status:
            print(f'  {model_name}: {", ".join(status)}')
        else:
            print(f'  {model_name}: nothing to do')

    print('\nDone.')


if __name__ == '__main__':
    main()
