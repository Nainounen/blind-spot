(request => {
    try {
    const fail = message => JSON.stringify({ error: message });
    const norm = s => String(s == null ? "" : s).replace(/\uFEFF/g, "").replace(/\s+/g, " ").trim();
    const text = el => norm(el ? el.textContent : "");
    const all = (sel, node) => [...(node || document).querySelectorAll(sel)];
    const visible = el => {
        if (!el) return false;
        const r = el.getBoundingClientRect();
        return r.width > 0 && r.height > 0;
    };
    const letter = i => String.fromCharCode(65 + (i % 26));

    // ─────────────────────────────────────────────────────────────
    //  Detection
    // ─────────────────────────────────────────────────────────────

    // Moodle wraps each question in <div class="que ...">. Generic fallback groups
    // form controls by their nearest fieldset/form/section/question container.
    function containers() {
        const moodle = all('.que').filter(visible);
        if (moodle.length) return moodle;
        const controls = all('input:not([type=hidden]), select, textarea, [contenteditable="true"]').filter(visible);
        const out = [];
        const seen = new Set();
        for (const c of controls) {
            const box = c.closest('fieldset, [data-question], .question, section, article')
                     || c.closest('form')
                     || c.parentElement;
            if (!box || seen.has(box)) continue;
            seen.add(box);
            out.push(box);
        }
        return out;
    }

    function classify(que) {
        const cls = (que.className || "").toString();
        const radios = all('input[type=radio]', que).filter(visible);
        const checkboxes = all('input[type=checkbox]', que).filter(visible);
        const selects = all('select', que).filter(visible);
        const textareas = all('textarea', que).filter(visible);
        const richtext = all('[contenteditable="true"]', que).filter(visible);
        const textInputs = all('input[type=text], input[type=number], input[type=email], input:not([type])', que)
            .filter(v => visible(v) && !v.disabled && !v.readOnly);
        if (cls.includes('multianswer') || cls.includes('cloze')) return 'cloze';
        if (cls.includes('ddimageortext')) return 'ddimageortext';
        if (cls.includes('ddmarker')) return 'ddmarker';
        if (cls.includes('ddwtos')) return 'ddwtos';
        if (cls.includes('truefalse')) return 'truefalse';
        if (checkboxes.length) return 'multi';
        if (radios.length) return 'single';
        if (cls.includes('ordering')) return 'order';
        if (cls.includes('match')) return 'match';
        // Numerical must be checked before the generic selects branch: a numerical
        // question with units (<showunits>0</showunits>) renders a number input AND a
        // units <select>, so letting the select win would skip the number entirely.
        if (cls.includes('numerical')) return 'numerical';
        if (selects.length) return 'select';
        if (cls.includes('essay')) return 'textarea';
        if (textareas.length) return 'textarea';
        if (richtext.length) return 'rich';
        if (textInputs.length) return 'text';
        return null;
    }

    function choiceLabel(input) {
        try {
            if (input.id) {
                const l = document.querySelector('label[for="' + input.id.replace(/"/g, '\\"') + '"]');
                if (l) { const t = text(l); if (t) return t; }
            }
        } catch (e) {}
        const wrap = input.closest('label, .r0, .r1, .answer-item, li, td');
        if (wrap) {
            const clone = wrap.cloneNode(true);
            all('input', clone).forEach(x => x.remove());
            const t = text(clone);
            if (t) return t;
        }
        return input.value || "";
    }

    function selectLabel(sel) {
        const row = sel.closest('tr, li, .answer-item, .felement');
        if (row) {
            const clone = row.cloneNode(true);
            all('select', clone).forEach(x => x.remove());
            const t = text(clone);
            if (t) return t;
        }
        try {
            if (sel.id) {
                const l = document.querySelector('label[for="' + sel.id.replace(/"/g, '\\"') + '"]');
                if (l) { const t = text(l); if (t) return t; }
            }
        } catch (e) {}
        return sel.name || "";
    }

    function choicesOf(que) {
        return all('input[type=radio], input[type=checkbox]', que)
            .filter(visible)
            .map((inp, i) => ({ letter: letter(i), text: choiceLabel(inp) }));
    }

    function selectsOf(que) {
        const qtext = que.querySelector('.qtext');
        const embedded = new Map();
        if (qtext) all('select', qtext).filter(visible).forEach((s, i) => embedded.set(s, i));
        return all('select', que).filter(visible).map(sel => ({
            label: embedded.has(sel) ? ('Gap ' + (embedded.get(sel) + 1)) : selectLabel(sel),
            options: [...sel.options].map(o => norm(o.text)).filter(t => t)
        }));
    }

    function orderItemsOf(que) {
        return all('.sortablelist li, ul.sortablelist > li, ol.sortablelist > li', que)
            .filter(visible)
            .map(li => { const c = li.cloneNode(true); all('input', c).forEach(x => x.remove()); return text(c); })
            .filter(t => t);
    }

    function hasImage(que) {
        return all('img', que).some(img => {
            const r = img.getBoundingClientRect();
            return r.width > 24 && r.height > 24;
        });
    }

    // For question types whose controls live inside the question text (cloze, gapselect,
    // ddwtos), render the stem with a "[Gap N]" placeholder in place of each control so the
    // text reads cleanly and the AI sees a numbered gap instead of raw form markup.
    const BLOCK = new Set(['BR', 'P', 'DIV', 'LI', 'UL', 'OL', 'TR', 'TD', 'TH', 'TABLE',
        'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'SECTION', 'ARTICLE', 'BLOCKQUOTE', 'FIGCAPTION']);
    function renderStem(qtext, placeholders) {
        const out = [];
        const skip = el => el.classList && (
            el.classList.contains('accesshide') || el.classList.contains('visually-hidden') ||
            el.classList.contains('sr-only') || el.classList.contains('subq'));
        const visit = node => {
            if (node.nodeType === 3) { out.push(node.textContent); return; }
            if (node.nodeType !== 1) return;
            const el = node;
            if (placeholders.has(el)) { out.push(placeholders.get(el)); return; }
            if (skip(el)) return;
            if (BLOCK.has(el.tagName)) out.push(' ');
            for (const child of el.childNodes) visit(child);
            if (BLOCK.has(el.tagName)) out.push(' ');
        };
        visit(qtext);
        return norm(out.join(''));
    }

    // Enumerate the sub-questions embedded in a multianswer/cloze question, in DOM order.
    // A MULTICHOICE renders as a <select>, SHORTANSWER and NUMERICAL as <input type=text>,
    // and MCV/MCH as a group of radios sharing one name (one gap for the whole group).
    // Returns {gaps, roots} where roots[i] is the DOM element rendering gap i, so apply can
    // re-locate the exact control without re-indexing ambiguity.
    function clozeGaps(que) {
        const qtext = que.querySelector('.qtext') || que;
        const controls = all('select, input[type=text], input[type=number], input[type=radio]', qtext)
            .filter(visible);
        const gaps = [], roots = [];
        const seenRadio = new Set();
        for (const c of controls) {
            if (c.type === 'radio') {
                if (seenRadio.has(c.name)) continue;
                seenRadio.add(c.name);
                const radios = all('input[type=radio]', qtext).filter(r => r.name === c.name && visible(r));
                roots.push(radios[0].closest('fieldset') || radios[0].parentElement);
                gaps.push({ type: 'radio', options: radios.map(choiceLabel) });
            } else if (c.tagName === 'SELECT') {
                roots.push(c.closest('.subquestion, .control') || c);
                gaps.push({ type: 'select', options: [...c.options].map(o => norm(o.text)).filter(t => t) });
            } else {
                roots.push(c.closest('.subquestion, .control') || c);
                gaps.push({ type: 'text' });
            }
        }
        return { gaps, roots };
    }

    // describe() returns the serializable question for a container, or null if unclassifiable.
    function describe(que) {
        const kind = classify(que);
        if (!kind) return null;
        const qtext = que.querySelector('.qtext') || que;
        const q = { kind, text: "", hasImage: hasImage(que), choices: [], selects: [], orderItems: [], gaps: [], dropZones: 0, dragItems: [], units: null, rect: null };
        const placeholders = new Map(); // DOM element -> "[Gap N]" label

        if (kind === 'cloze') {
            const cg = clozeGaps(que);
            q.gaps = cg.gaps;
            cg.roots.forEach((r, i) => placeholders.set(r, '[Gap ' + (i + 1) + ']'));
        } else if (kind === 'select' || kind === 'match') {
            all('select', qtext).filter(visible).forEach((s, i) => placeholders.set(s, '[Gap ' + (i + 1) + ']'));
        } else if (kind === 'ddwtos') {
            q.dropZones = all('.drop', qtext).length;
            q.dragItems = all('.draghome', que).map(t => text(t)).filter(t => t);
            all('.drop', qtext).forEach((d, i) => placeholders.set(d, '[Gap ' + (i + 1) + ']'));
        } else if (kind === 'ddimageortext') {
            q.dropZones = all('.dropzone', que).length;
            q.dragItems = all('.draghome', que).map(t => text(t)).filter(t => t);
        } else if (kind === 'ddmarker') {
            q.dropZones = all('.dropzone', que).length;
            q.dragItems = all('.dragitem', que).map(t => text(t)).filter(t => t);
        } else if (kind === 'numerical') {
            // A numerical question with units renders a units <select> alongside the
            // number input. Expose the unit options so the AI can answer both at once.
            const unitSel = all('select', que).filter(visible)[0];
            if (unitSel) q.units = [...unitSel.options].map(o => norm(o.text)).filter(t => t);
        }

        q.text = renderStem(qtext, placeholders);
        if (kind === 'single' || kind === 'multi' || kind === 'truefalse') q.choices = choicesOf(que);
        else if (kind === 'select' || kind === 'match') q.selects = selectsOf(que);
        else if (kind === 'order') q.orderItems = orderItemsOf(que);
        const r = que.getBoundingClientRect();
        q.rect = [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)];
        return q;
    }

    // detectAll() keeps the container element alongside the serializable question,
    // so apply can operate on the exact element without re-indexing ambiguity.
    function detectAll() {
        const out = [];
        containers().forEach(el => {
            const q = describe(el);
            if (q) out.push({ el, q });
        });
        return out;
    }

    function serialize(includeRect) {
        return detectAll().map((f, i) => {
            const q = Object.assign({ index: i }, f.q);
            if (!includeRect) delete q.rect;
            return q;
        });
    }

    function fingerprint() {
        // q.rect comes from getBoundingClientRect(), which changes with any scroll/resize
        // between extract and apply — omit it so the fingerprint only reflects stable state.
        return JSON.stringify([location.href, performance.timeOrigin, document.title, serialize(false)]);
    }

    // ─────────────────────────────────────────────────────────────
    //  Extract
    // ─────────────────────────────────────────────────────────────

    if (request.action === "extract") {
        const questions = serialize(true);
        // Empty questions is a normal end-of-exam state for answer-all; the caller
        // decides whether it's an error (single mode) or time to stop (answer-all).
        return JSON.stringify({
            url: location.href,
            title: document.title,
            questions,
            fingerprint: fingerprint()
        });
    }

    // ─────────────────────────────────────────────────────────────
    //  Next page (Moodle one-question-per-page navigation)
    // ─────────────────────────────────────────────────────────────

    if (request.action === "next") {
        const before = location.href;
        const candidates = all('input[type=submit][name=next], button[name=next]');
        let btn = candidates.find(visible);
        if (!btn) {
            btn = all('input[type=submit], button[type=submit], button')
                .find(b => /^next\b/i.test(norm(b.value || b.textContent)) && visible(b));
        }
        if (!btn) return JSON.stringify({ navigated: false });
        if (btn.disabled || btn.getAttribute('aria-disabled') === 'true') {
            return JSON.stringify({ navigated: false });
        }
        // The click only *starts* an asynchronous navigation — location.href has not
        // moved yet within this same task, so it can't be confirmed synchronously.
        // Hand the pre-click state back so the caller can verify the page advanced.
        const beforeFingerprint = fingerprint();
        btn.click();
        return JSON.stringify({ navigated: true, url: before, fingerprint: beforeFingerprint });
    }

    // ─────────────────────────────────────────────────────────────
    //  Apply
    // ─────────────────────────────────────────────────────────────

    if (request.action !== "apply") return fail("Unknown browser action.");
    if (request.fingerprint && request.fingerprint !== fingerprint()) {
        return fail("The page or questions changed. Run Auto-Answer again on the current page.");
    }

    const found = detectAll();
    let answers = request.answers;
    if (typeof answers === 'string') {
        try { answers = JSON.parse(answers); } catch (e) { return fail("The AI returned unparseable answers."); }
    }
    const list = Array.isArray(answers) ? answers : (answers && Array.isArray(answers.answers) ? answers.answers : null);
    if (!list) return fail("The AI returned no answers.");

    const setValue = (field, value) => {
        const proto = field.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype
            : field.tagName === 'SELECT' ? HTMLSelectElement.prototype
            : HTMLInputElement.prototype;
        const desc = Object.getOwnPropertyDescriptor(proto, 'value');
        if (desc && desc.set) desc.set.call(field, value);
        else field.value = value;
        field.dispatchEvent(new Event('input', { bubbles: true }));
        field.dispatchEvent(new Event('change', { bubbles: true }));
    };

    function optionIndex(inputs, value) {
        const v = String(value).trim().toUpperCase();
        let idx = -1;
        if (/^[A-Z]$/.test(v)) idx = v.charCodeAt(0) - 65;
        else if (/^\d+$/.test(v)) idx = parseInt(v, 10);
        if (idx >= 0 && idx < inputs.length) return idx;
        return inputs.findIndex(inp => norm(choiceLabel(inp)).toUpperCase() === String(value).trim().toUpperCase());
    }

    const results = [];
    for (const a of list) {
        const entry = found[a.index];
        if (!entry) { results.push({ index: a.index, filled: false, error: "unknown question" }); continue; }
        const q = entry.q, el = entry.el, v = a.value;
        try {
            if (q.kind === 'single' || q.kind === 'truefalse') {
                const inputs = all('input[type=radio]', el).filter(visible);
                const idx = optionIndex(inputs, v);
                if (idx < 0) throw new Error("no matching option for \"" + v + "\"");
                inputs[idx].click();
                results.push({ index: a.index, filled: true });
            } else if (q.kind === 'multi') {
                const inputs = all('input[type=checkbox]', el).filter(visible);
                const vals = Array.isArray(v) ? v : String(v).split(/[,;]/);
                const want = new Set();
                vals.forEach(val => { const idx = optionIndex(inputs, val); if (idx >= 0) want.add(idx); });
                // Set each checkbox to the desired state explicitly (click() would toggle),
                // then verify the final state matches the plan before reporting success.
                inputs.forEach((inp, i) => {
                    const checked = want.has(i);
                    inp.checked = checked;
                    inp.dispatchEvent(new Event('change', { bubbles: true }));
                    inp.dispatchEvent(new Event('input', { bubbles: true }));
                });
                const ok = inputs.every((inp, i) => inp.checked === want.has(i));
                results.push({ index: a.index, filled: want.size > 0 && ok });
            } else if (q.kind === 'textarea' || q.kind === 'rich') {
                const text = String(v);
                const ta = all('textarea', el)[0]; // may be hidden behind an editor
                let filled = false;
                // TinyMCE (iframe) — set content through its API.
                if (!filled && typeof window.tinymce !== 'undefined' && ta && ta.id && window.tinymce.get && window.tinymce.get(ta.id)) {
                    window.tinymce.get(ta.id).setContent(text);
                    filled = true;
                }
                // Contenteditable editor (Atto / inline).
                if (!filled) {
                    const ce = all('[contenteditable="true"]', el).filter(visible)[0];
                    if (ce) {
                        ce.focus();
                        const range = document.createRange();
                        range.selectNodeContents(ce);
                        const sel = window.getSelection();
                        sel.removeAllRanges(); sel.addRange(range);
                        document.execCommand('insertText', false, text);
                        ce.dispatchEvent(new Event('input', { bubbles: true }));
                        filled = true;
                    }
                }
                // Plain or hidden textarea fallback.
                if (!filled && ta) { setValue(ta, text); filled = true; }
                if (!filled) throw new Error("no essay field");
                results.push({ index: a.index, filled: true });
            } else if (q.kind === 'text' || q.kind === 'numeric' || q.kind === 'numerical') {
                // Numerical with units: v may be a plain string ("1024", unit left
                // unfilled) or an object {"value":"1024","unit":"B"}.
                let value = v, unit = null;
                if (v && typeof v === 'object' && !Array.isArray(v)) {
                    value = v.value;
                    unit = v.unit;
                }
                const fields = all('input[type=text], input[type=number], input:not([type])', el).filter(visible);
                if (!fields.length) throw new Error("no text field");
                setValue(fields[0], String(value == null ? "" : value));
                let filled = true;
                if (unit != null) {
                    const sel = all('select', el).filter(visible)[0];
                    if (!sel) throw new Error("no unit dropdown");
                    const opt = [...sel.options].find(o => norm(o.text) === String(unit).trim() || o.value === String(unit).trim());
                    if (opt) setValue(sel, opt.value);
                    else filled = false;
                }
                results.push({ index: a.index, filled });
            } else if (q.kind === 'select' || q.kind === 'match') {
                const sels = all('select', el).filter(visible);
                const vals = Array.isArray(v) ? v : [v];
                let hit = 0;
                sels.forEach((s, i) => {
                    const target = vals[i];
                    if (target == null) return; // fewer AI values than dropdowns → left unfilled
                    const opt = [...s.options].find(o => norm(o.text) === String(target).trim() || o.value === String(target).trim());
                    if (opt) { setValue(s, opt.value); hit++; }
                });
                results.push({ index: a.index, filled: sels.length > 0 && hit === sels.length });
            } else if (q.kind === 'cloze') {
                const cg = clozeGaps(el);
                const gaps = cg.gaps, roots = cg.roots;
                const vals = Array.isArray(v) ? v : [v];
                let filled = 0;
                for (let i = 0; i < gaps.length; i++) {
                    const target = vals[i];
                    if (target == null) continue; // fewer AI values than gaps → left unfilled
                    const g = gaps[i], root = roots[i];
                    if (g.type === 'text') {
                        const inp = root.tagName === 'INPUT'
                            ? root
                            : all('input[type=text], input[type=number]', root).filter(visible)[0];
                        if (!inp) throw new Error("no text field for gap " + (i + 1));
                        setValue(inp, String(target)); filled++;
                    } else if (g.type === 'select') {
                        const sel = root.tagName === 'SELECT' ? root : all('select', root).filter(visible)[0];
                        if (!sel) throw new Error("no dropdown for gap " + (i + 1));
                        const opt = [...sel.options].find(o => norm(o.text) === String(target).trim() || o.value === String(target).trim());
                        if (opt) { setValue(sel, opt.value); filled++; }
                    } else { // radio
                        const radios = root.tagName === 'INPUT' ? [root] : all('input[type=radio]', root).filter(visible);
                        const idx = optionIndex(radios, target);
                        if (idx < 0) throw new Error("no matching option for \"" + target + "\" in gap " + (i + 1));
                        radios[idx].click(); filled++;
                    }
                }
                results.push({ index: a.index, filled: gaps.length > 0 && filled === gaps.length });
            } else if (q.kind === 'ddwtos') {
                // Drag-and-drop can't be filled reliably from extracted text — always flag it
                // for manual review rather than silently writing a wrong answer.
                results.push({ index: a.index, filled: false, error: "drag-and-drop needs manual check" });
            } else if (q.kind === 'ddimageortext') {
                // Drop coordinates are image-relative and can't be set from text — never
                // attempt an auto-fill; always flag for manual review.
                results.push({ index: a.index, filled: false, error: "drag-and-drop onto image needs manual check" });
            } else if (q.kind === 'ddmarker') {
                // Marker drop coordinates are image-relative and can't be set from text —
                // never attempt an auto-fill; always flag for manual review.
                results.push({ index: a.index, filled: false, error: "drag-and-drop markers needs manual check" });
            } else if (q.kind === 'order') {
                // Ordering (drag-and-drop) can't be filled reliably by writing labels into
                // hidden position fields — always flag it for a manual check, never
                // silently write labels as positions.
                results.push({ index: a.index, filled: false, error: "ordering needs manual check" });
            } else {
                results.push({ index: a.index, filled: false, error: "unsupported kind " + q.kind });
            }
        } catch (e) {
            results.push({ index: a.index, filled: false, error: String((e && e.message) || e) });
        }
    }

    const failed = results.filter(r => !r.filled);
    if (!results.some(r => r.filled)) {
        return fail("Could not fill any question: " +
            failed.map(r => "Q" + (r.index + 1) + " (" + (r.error || "unfilled") + ")").join("; "));
    }
    return JSON.stringify({ applied: failed.length === 0, results });
    } catch (e) {
        const msg = e && e.message ? e.message : String(e);
        const stack = e && e.stack ? String(e.stack) : "";
        return JSON.stringify({ error: "JS exception: " + msg + (stack ? " @ " + stack.split("\n").slice(1, 3).join(" ") : "") });
    }
})
