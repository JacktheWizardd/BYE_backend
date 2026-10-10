(() => {
    const store = window.__RELAY_STORE__ || {};
    const text = (node) => node ? node.textContent.trim() : '';
    const visibleSourceText = (value) => {
        // Source comments can contain encoded entities; DOM textContent already shows their visible wording.
        const decoder = document.createElement?.('textarea');
        if (!decoder) return String(value);
        decoder.innerHTML = String(value);
        return decoder.value;
    };
    const normalizedComment = (value) => value.replace(/\s+/g, ' ').trim();
    const normalizedCourse = (value) => value.replace(/\s+/g, '').toUpperCase();
    const number = (value, min, max) => {
        if (value === null || value === undefined || value === '') return null;
        const n = Number(value);
        return Number.isFinite(n) && n >= min && n <= max ? n : null;
    };
    const teachers = Object.values(store).filter(x => x && x.__typename === 'Teacher' && x.legacyId);
    const profileID = (location.pathname.match(/\/professor\/(\d+)/) || [])[1];
    const candidates = teachers.filter(t => !profileID || String(t.legacyId) === profileID).map(t => {
        const school = store[t.school && t.school.__ref] || {};
        const count = number(t.numRatings, 0, 1000000);
        return {
            id: String(t.legacyId), firstName: t.firstName || '', lastName: t.lastName || '',
            school: school.name || '', schoolID: number(school.legacyId, 1, 1000000), department: t.department || '',
            rating: count === 0 ? null : number(t.avgRating, 1, 5),
            difficulty: count === 0 ? null : number(t.avgDifficulty, 1, 5), ratingCount: count,
            wouldTakeAgain: number(t.wouldTakeAgainPercent, 0, 100), reviews: []
        };
    });
    if (!profileID) {
        // Search pagination can update React's DOM without replacing the hydration store.
        document.querySelectorAll('a[class*="TeacherCard__StyledTeacherCard"]').forEach(card => {
            const id = (card.getAttribute('href') || '').match(/\/professor\/(\d+)/)?.[1];
            if (!id || candidates.some(p => p.id === id)) return;
            const name = text(card.querySelector('[class*="CardName__StyledCardName"]')).split(/\s+/);
            const school = text(card.querySelector('[class*="CardSchool__School"]'));
            if (name.length < 2 || school !== 'Pasadena City College') return;
            candidates.push({id, firstName: name.shift(), lastName: name.join(' '), school, schoolID: 2649,
                department: text(card.querySelector('[class*="CardSchool__Department"]')),
                rating: null, difficulty: null, ratingCount: null, wouldTakeAgain: null, reviews: []});
        });
    }
    if (profileID && candidates.length === 1) {
        const teacher = teachers.find(t => String(t.legacyId) === profileID);
        const connectionKey = Object.keys(teacher).find(k => k.includes('RatingsList_ratings_connection')) ||
            Object.keys(teacher).find(k => k.startsWith('ratings('));
        const connection = store[teacher[connectionKey]?.__ref];
        const edgeIDs = connection?.edges?.__refs || [];
        let source = edgeIDs.map(id => store[store[id]?.node?.__ref]).filter(Boolean);
        if (!source.length) source = Object.values(store).filter(x => x && x.__typename === 'Rating');
        const reviews = source.filter(r => r.comment && r.flagStatus !== 'DELETED').map(r => ({
            id: String(r.legacyId || r.id), course: r.class || '', text: visibleSourceText(r.comment),
            date: (r.date || '').slice(0, 10),
            rating: number(r.helpfulRating, 1, 5), difficulty: number(r.difficultyRating, 1, 5),
            online: typeof r.isForOnlineClass === 'boolean' ? r.isForOnlineClass : null
        }));
        // Public Load More buttons update the rendered cards even when the initial hydration store is unchanged.
        document.querySelectorAll('[class*="Rating__RatingBody"]').forEach(card => {
            const comment = text(card.querySelector('[class*="Comments__StyledComments"]'));
            if (!comment) return;
            const course = text(card.querySelector('[class*="RatingHeader__StyledClass"]'));
            const stamp = text(card.querySelector('[class*="RatingHeader__RatingTimeStamp"]'));
            const parsed = new Date(stamp.replace(/(\d+)(st|nd|rd|th)/g, '$1'));
            const date = Number.isNaN(parsed.getTime()) ? '' : parsed.toISOString().slice(0, 10);
            // The public flag link identifies a review without activating that link.
            // Verify the professor segment before accepting its source review ID.
            const sourceLinks = [...card.querySelectorAll('a[href*="/flag/professor-rating/"]')]
                .map(link => (link.getAttribute('href') || '').match(/\/flag\/professor-rating\/(\d+)\/(\d+)(?:[/?#]|$)/))
                .filter(Boolean);
            const sourceID = sourceLinks.find(match => match[1] === profileID)?.[2];
            if (sourceLinks.length && !sourceID) return;
            if (!sourceID && reviews.some(r => normalizedComment(r.text) === normalizedComment(comment) &&
                (!r.course || !course || normalizedCourse(r.course) === normalizedCourse(course)) &&
                (!r.date || !date || r.date === date))) return;
            const metrics = [...card.querySelectorAll('[class*="CardNumRating__StyledCardNumRating"]')];
            const metric = (label) => {
                const item = metrics.find(n => new RegExp(label, 'i').test(n.textContent));
                return number(text(item?.querySelector('[class*="CardNumRating__CardNumRatingNumber"]')), 1, 5);
            };
            const rating = metric('quality'), difficulty = metric('difficulty');
            const existing = sourceID ? reviews.find(r => r.id === sourceID) : null;
            if (existing) {
                // The site's visible posted date can differ from its embedded UTC date.
                Object.assign(existing, {course: course || existing.course, text: comment,
                    date: date || existing.date, rating: rating ?? existing.rating,
                    difficulty: difficulty ?? existing.difficulty});
            } else {
                reviews.push({id: sourceID || 'dom-' + course + '-' + stamp + '-' + comment.slice(0, 80),
                    course, text: comment, date, rating, difficulty, online: null});
            }
        });
        candidates[0].reviews = reviews.slice(0, 50);
    }
    return JSON.stringify(candidates);
})()
