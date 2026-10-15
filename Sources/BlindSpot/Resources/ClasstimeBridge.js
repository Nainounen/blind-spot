(request => {
    const fail = message => JSON.stringify({ error: message });
    const normalize = value => String(value || "").replace(/\uFEFF/g, "").replace(/\s+/g, " ").trim();
    const text = element => normalize(element?.textContent);
    const all = (selector, node = root) => [...node.querySelectorAll(selector)];
    const root = document.querySelector('main[aria-label="Question content"]');
    if (!root) return fail("Open a Classtime question before using Auto-Answer.");
    const title = text(root.querySelector('[data-testid="student-session-question-title"]'));
    const number = text(root.querySelector('[data-testid="student-session-question-number"]'));
    if (!title) return fail("The question has not finished loading.");
    const description = text(root.querySelector('[class*="paragraphWithLinks"]'));
    const list = root.querySelector('[data-testid="questions-answers-list"]');
    const wrappers = list ? all('[data-testid="choice-wrapper"]', list) : [];
    const inputs = wrappers.map(node => node.querySelector('input[type="radio"], input[type="checkbox"]'));
    const rows = all('[data-testid="question-answer-row"]');
    const cards = all('[data-testid="student-sorter-choice-wrapper"]');
    const gaps = all('[data-testid="fitg-pointer-blank"]');
    const preview = root.querySelector('[data-testid="highlight-text-preview"]');
    const groups = preview ? all('[role="group"]', preview).filter(group =>
        group.querySelector('[data-testid="highlight-text-choice"]') &&
        !all('[role="group"]', group).some(child => child.querySelector('[data-testid="highlight-text-choice"]'))) : [];
    const editors = all('[data-slate-editor="true"][contenteditable="true"]');
    const fields = all('textarea:not([disabled]):not([readonly])').filter(node => node.getClientRects().length > 0);
    let kind, options = [], details = {}, state, answerFormat, controls = [], maxSteps = 4;
    const choiceState = button => {
        const input = button.matches('input') ? button : button.querySelector('input');
        if (input && ['radio', 'checkbox'].includes(input.type)) return input.checked;
        for (const key of ['aria-pressed', 'aria-checked', 'aria-selected', 'data-selected']) {
            if (button.hasAttribute(key)) return button.getAttribute(key) === 'true';
        }
        return null;
    };
    if (root.querySelector('[data-testid="student-categorizer-answers-form"]') && rows.length) {
        kind = "categorizer";
        const categories = all('[data-testid="category-header-cell"]').map(text);
        controls = rows.map(row => all('td', row).map(cell => cell.querySelector('input[type="radio"], input[type="checkbox"]')));
        if (!categories.length || controls.some(row => row.length !== categories.length || row.some(cell => !cell))) {
            return fail("The category table layout is not supported.");
        }
        details = { items: rows.map(row => text(row.querySelector('th'))), categories,
            multiplePerRow: controls.map(row => row.every(cell => cell.type === 'checkbox')) };
        if (controls.some((row, i) => !details.multiplePerRow[i] && !row.every(cell => cell.type === 'radio'))) {
            return fail("The category table has mixed controls.");
        }
        state = controls.map(row => row.map(cell => cell.checked));
        answerFormat = 'Return {"categories":[[0],[1]]}: one array per item, containing zero-based category indices. Select exactly one category for radio rows; all correct categories for checkbox rows.';
        maxSteps = controls.flat().length + 2;
    } else if (cards.length) {
        kind = "sorter";
        state = cards.map(card => text(card.querySelector('[data-testid="student-sorter-choice-content"]')));
        if (state.some(label => !label) || new Set(state).size !== state.length) return fail("Ordering requires distinct item labels.");
        options = [...state].sort();
        details = { items: options };
        controls = cards;
        answerFormat = 'Return {"order":[2,0,1]}: every zero-based item index exactly once, in the requested order.';
        maxSteps = cards.length * cards.length + 2;
    } else if (gaps.length) {
        kind = "gaps";
        if (!list || gaps.some(gap => !list.contains(gap))) {
            return fail("This gap layout does not expose a matching answer passage.");
        }
        controls = gaps.map(gap => gap.querySelector('textarea, input, select'));
        if (controls.some(field => !field)) return fail("A gap has no supported input control.");
        const copy = list.cloneNode(true);
        all('[data-testid="fitg-pointer-blank"]', copy).forEach((gap, i) => gap.replaceWith(` [Gap ${i + 1}] `));
        details = { passage: text(copy), gaps: controls.map(field => field.tagName === 'SELECT'
            ? [...field.options].map(option => ({ text: option.text, value: option.value, disabled: option.disabled })) : null) };
        state = controls.map(field => field.value);
        answerFormat = 'Return {"fills":["first answer","second answer"]}, one string for each gap. For a select gap, use the exact option value.';
        maxSteps = controls.length + 2;
    } else if (groups.length) {
        kind = "cloze";
        controls = groups.map(group => all('[data-testid="highlight-text-choice"]', group));
        state = controls.map(group => group.map(choiceState));
        if (state.flat().some(value => value === null)) return fail("This cloze layout does not expose selection state. BlindSpot cannot verify filling it.");
        details = { groups: controls.map(group => group.map(text)) };
        const copy = preview.cloneNode(true);
        all('[data-testid="highlight-text-choice"]', copy).forEach(button => button.replaceWith(' [choice] '));
        details.passage = text(copy);
        answerFormat = 'Return {"choices":[0,1]}: one zero-based option index per gap group.';
        maxSteps = controls.flat().length + 2;
    } else if (editors.length === 1) {
        kind = "richText";
        controls = editors;
        state = text(editors[0]);
        answerFormat = 'Return {"text":"answer"}. Write the answer as plain text, without Markdown formatting.';
    } else if (inputs.length >= 2 && inputs.every(Boolean)) {
        if (inputs.every(input => input.type === 'radio')) kind = "single";
        else if (inputs.every(input => input.type === 'checkbox')) kind = "multiple";
        options = wrappers.map(node => text(node.querySelector('label')));
        controls = inputs;
        state = inputs.map(input => input.checked);
        answerFormat = 'Return {"indices":[1]} with zero-based option indices. ' + (kind === 'single' ? 'Choose exactly one option.' : 'Choose every correct option.');
        maxSteps = inputs.length + 2;
    } else if (fields.length === 1) {
        kind = "text";
        controls = fields;
        state = fields[0].value;
        answerFormat = 'Return {"text":"answer"}.';
    }
    if (!kind) return fail("This Classtime question type is not supported yet.");
    if (controls.flat().some(control => control.disabled || control.readOnly || control.getAttribute('aria-disabled') === 'true')) {
        return fail("This question is read-only.");
    }
    const fingerprint = JSON.stringify([location.href, performance.timeOrigin, number, title, description, kind, options, details]);
    if (request.action === "extract") return JSON.stringify({ title, description, kind, options, details: JSON.stringify(details), answerFormat, maxSteps,
        fingerprint, state: JSON.stringify(state) });
    if (request.action !== "apply") return fail("Unknown browser action.");
    if (request.fingerprint !== fingerprint) return fail("The page or question changed. Try again on the current question.");
    if (request.state !== JSON.stringify(state)) return fail("The answer changed or Classtime did not retain the last update. No further changes were made.");
    const answer = request.answer;
    const pending = (expected, phase = "") => JSON.stringify({ pending: true, state: JSON.stringify(expected), phase });
    const validIndices = (values, count, single = false) => Array.isArray(values) && values.length > 0 &&
        (!single || values.length === 1) && new Set(values).size === values.length &&
        values.every(index => Number.isInteger(index) && index >= 0 && index < count);
    const validText = value => typeof value === 'string' && value.trim().length > 0 && value.length <= 20000;
    const setValue = (field, value) => {
        const prototype = field.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype :
            field.tagName === 'SELECT' ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(prototype, 'value').set.call(field, value);
        field.dispatchEvent(new Event('input', { bubbles: true }));
        field.dispatchEvent(new Event('change', { bubbles: true }));
    };
    if (kind === 'sorter') {
        if (!validIndices(answer?.order, options.length) || answer.order.length !== options.length) return fail("The AI returned an invalid item order.");
        const target = answer.order.map(index => options[index]);
        const first = state.findIndex((label, i) => label !== target[i]);
        if (first >= 0) {
            const from = state.indexOf(target[first]);
            const button = cards[from].querySelector('[data-testid="student-sorter-choice-move-up"]');
            if (!button || button.disabled) return fail("This ordering layout does not expose a working move-up control.");
            const expected = [...state];
            [expected[from - 1], expected[from]] = [expected[from], expected[from - 1]];
            button.click();
            return pending(expected);
        }
    } else if (kind === 'categorizer') {
        if (!Array.isArray(answer?.categories) || answer.categories.length !== controls.length ||
            answer.categories.some((indices, i) => !validIndices(indices, details.categories.length, !details.multiplePerRow[i]))) {
            return fail("The AI returned invalid category assignments.");
        }
        for (let row = 0; row < controls.length; row++) {
            for (let col = 0; col < controls[row].length; col++) {
                const desired = answer.categories[row].includes(col);
                if (state[row][col] !== desired && (details.multiplePerRow[row] || desired)) {
                    const expected = state.map(values => [...values]);
                    expected[row] = details.multiplePerRow[row] ? expected[row] : controls[row].map((_, i) => i === col);
                    expected[row][col] = desired;
                    controls[row][col].click();
                    return pending(expected);
                }
            }
        }
    } else if (kind === 'gaps') {
        if (!Array.isArray(answer?.fills) || answer.fills.length !== controls.length || answer.fills.some((value, i) =>
            !validText(value) || (details.gaps[i] && !details.gaps[i].some(option => option.value === value && !option.disabled)))) {
            return fail("The AI returned invalid gap answers.");
        }
        for (let i = 0; i < controls.length; i++) {
            if (state[i] !== answer.fills[i]) {
                const expected = [...state]; expected[i] = answer.fills[i];
                setValue(controls[i], answer.fills[i]);
                return pending(expected);
            }
        }
    } else if (kind === 'cloze') {
        if (!Array.isArray(answer?.choices) || answer.choices.length !== controls.length ||
            answer.choices.some((index, i) => !validIndices([index], controls[i].length, true))) return fail("The AI returned invalid cloze choices.");
        for (let i = 0; i < controls.length; i++) {
            const index = answer.choices[i];
            if (!state[i][index]) {
                const expected = state.map(values => [...values]);
                expected[i] = controls[i].map((_, j) => j === index);
                controls[i][index].click();
                return pending(expected);
            }
            if (state[i].filter(Boolean).length !== 1) return fail("This cloze group has more than one selection. Check it manually.");
        }
    } else if (kind === 'richText' || kind === 'text') {
        if (!validText(answer?.text)) return fail("The AI returned an invalid text answer.");
        const desired = kind === 'richText' ? normalize(answer.text) : answer.text;
        if (state !== desired) {
            const field = controls[0];
            if (kind === 'text') setValue(field, answer.text);
            else if (request.phase !== 'richInsert') {
                field.focus();
                const range = document.createRange(); range.selectNodeContents(field);
                const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
                return pending(state, 'richInsert');
            } else {
                const selection = window.getSelection();
                if (document.activeElement !== field || !selection?.rangeCount ||
                    !field.contains(selection.anchorNode) || !field.contains(selection.focusNode) || normalize(selection.toString()) !== state) {
                    return fail("The editor focus or selection changed. Your text was kept.");
                }
                field.dispatchEvent(new InputEvent('beforeinput', { inputType: 'insertText', data: answer.text, bubbles: true, cancelable: true }));
            }
            return pending(desired);
        }
    } else {
        if (!validIndices(answer?.indices, inputs.length, kind === 'single')) return fail("The AI returned invalid answer choices.");
        for (let i = 0; i < inputs.length; i++) {
            const desired = answer.indices.includes(i);
            if (state[i] !== desired && (kind === 'multiple' || desired)) {
                const expected = kind === 'single' ? inputs.map((_, j) => j === i) : [...state]; expected[i] = desired;
                inputs[i].click(); return pending(expected);
            }
        }
    }
    return JSON.stringify({ applied: true });
})
