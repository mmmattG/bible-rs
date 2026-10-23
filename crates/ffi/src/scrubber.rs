//! The Scrubber: a rail along the reader's right edge that spans the whole Bible. Dragging along
//! it previews a place and letting go jumps there. The model is ported from Store the Word's
//! Scrubber (`ReaderScrubberAxis.swift`); the phone apps only draw it.
//!
//! The rail is weighted by verses, so a book takes as much of it as it takes of the Bible. A drag
//! starts at **Bible speed**, where the rail is the whole Bible. Dragging inward, away from the
//! edge, slows it to **Chapter speed**, which counts chapters (so a two-verse psalm takes as much
//! travel as a long one), and then **Verse speed**, which counts verses. Each speed carries on from
//! where the drag is rather than from where the finger is, so changing speed keeps the chapter.
//! Verse speed starts at the chapter's first verse, or at the verse it left if it comes back to
//! the same chapter.

use std::sync::{Arc, Mutex, MutexGuard};

use bible_core::books::CHAPTER_COUNT;
use bible_core::model::Translation;
use bible_core::{BookId, ChapterIdx};

/// How far inward (pt) a drag slows to Chapter speed, and to Verse speed.
const CHAPTER_INWARD: f64 = 60.0;
const VERSE_INWARD: f64 = 140.0;
/// How far back over a threshold (pt) a drag must come to speed up again, so a finger resting on
/// one doesn't flicker between speeds.
const HYSTERESIS: f64 = 16.0;
/// Finger travel (pt) per chapter at Chapter speed, and per verse at Verse speed.
const CHAPTER_STEP: f64 = 24.0;
const VERSE_STEP: f64 = 16.0;
/// A press this close (pt) to the thumb picks it up where it is; further away jumps the thumb to
/// the finger.
const GRAB: f64 = 44.0;

/// The parts of the Bible the Scrubber names, by first book (0 = Genesis), and whether the rail
/// marks where each starts. Revelation sits with the General Epistles, as in Store the Word.
const SECTIONS: [(u8, &str, bool); 8] = [
    (0, "Pentateuch", false),
    (5, "History", true),
    (17, "Wisdom and Poetry", true),
    (22, "Major Prophets", true),
    (27, "Minor Prophets", true),
    (39, "Gospels and Acts", true),
    (44, "Pauline Epistles", true),
    (57, "General Epistles", true),
];

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ScrubSpeed {
    /// The rail is the whole Bible.
    Bible,
    /// `CHAPTER_STEP` of travel per chapter.
    Chapter,
    /// `VERSE_STEP` of travel per verse; letting go lands on the verse.
    Verse,
}

impl ScrubSpeed {
    /// The speed a drag `inward` from the rail goes at, coming from this speed.
    fn at(self, inward: f64) -> ScrubSpeed {
        fn speed(distance: f64) -> ScrubSpeed {
            if distance >= VERSE_INWARD {
                ScrubSpeed::Verse
            } else if distance >= CHAPTER_INWARD {
                ScrubSpeed::Chapter
            } else {
                ScrubSpeed::Bible
            }
        }
        let finer = speed(inward);
        let coarser = speed(inward + HYSTERESIS);
        if finer.rank() > self.rank() {
            finer
        } else if coarser.rank() < self.rank() {
            coarser
        } else {
            self
        }
    }

    fn rank(self) -> u8 {
        match self {
            ScrubSpeed::Bible => 0,
            ScrubSpeed::Chapter => 1,
            ScrubSpeed::Verse => 2,
        }
    }
}

/// A place on the axis and what's there.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ScrubPoint {
    /// Verses from the start of Genesis 1.
    pub position: f64,
    /// `position` as a fraction of the whole Bible (0–1): where the thumb sits on the rail.
    pub fraction: f64,
    pub speed: ScrubSpeed,
    /// Where letting go lands: a chapter (0–1188), its book, and the verse at Verse speed (the
    /// chapter's first verse otherwise).
    pub chapter_index: u16,
    pub book: u8,
    pub verse: u8,
    /// "Psalm 23", or "Psalm 23:4" at Verse speed.
    pub reference: String,
    /// The part of the Bible the book is in: "Wisdom and Poetry".
    pub section: String,
}

/// A mark on the rail where a part of the Bible starts.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct ScrubLandmark {
    /// Where on the rail (0–1).
    pub fraction: f64,
    /// The start of the New Testament, marked more strongly.
    pub testament: bool,
}

/// The whole Bible as one axis, counted in a translation's verses: every verse it has is a stop,
/// and a verse it leaves out (Matthew 17:21 in many modern texts) isn't. A chapter it lacks keeps
/// its place, as the reader shows it, but as a single stop, so a New Testament alone fills most of
/// the rail. Without the translation the axis is the canonical grid.
#[derive(Debug, uniffi::Object)]
pub struct ScrubAxis {
    /// Each chapter's verse numbers, in order; never empty.
    verses: Vec<Vec<u8>>,
    /// Where each chapter starts, in verses from Genesis 1; the last entry is the Bible's length.
    starts: Vec<u32>,
}

impl ScrubAxis {
    pub(crate) fn new(translation: Option<&Translation>) -> Self {
        let verses: Vec<Vec<u8>> = ChapterIdx::all()
            .map(|c| match translation {
                Some(t) if t.has_chapter(c) => t.verses_in(c).map(|v| v.number).collect(),
                Some(_) => vec![1],
                None => (1..=c.kjv_verses()).collect(),
            })
            .collect();
        let mut starts = Vec::with_capacity(CHAPTER_COUNT + 1);
        starts.push(0);
        for numbers in &verses {
            starts.push(starts.last().unwrap() + numbers.len() as u32);
        }
        ScrubAxis { verses, starts }
    }

    fn start(&self, chapter: usize) -> f64 {
        self.starts[chapter] as f64
    }

    /// The chapter a position falls in (the first or last beyond the ends).
    fn chapter_at(&self, position: f64) -> usize {
        self.starts[..CHAPTER_COUNT].partition_point(|&s| s as f64 <= position).saturating_sub(1)
    }

    /// The thumb's place for a press at `y` on a track from `track_top` and `track_height` tall:
    /// the resting place if the press is on the thumb, otherwise wherever the finger is.
    fn pressed(&self, resting: f64, y: f64, track_top: f64, track_height: f64) -> f64 {
        let thumb = track_top + resting / self.length() * track_height;
        if (y - thumb).abs() <= GRAB {
            resting
        } else {
            ((y - track_top) / track_height).clamp(0.0, 1.0) * self.length()
        }
    }
}

#[uniffi::export]
impl ScrubAxis {
    /// The number of verses: 31,102 in the canonical grid.
    pub fn length(&self) -> f64 {
        self.starts[CHAPTER_COUNT] as f64
    }

    /// Where a verse starts on the axis. A verse the translation leaves out counts as the one
    /// before it.
    pub fn position(&self, chapter: u16, verse: u8) -> f64 {
        let c = (chapter as usize).min(CHAPTER_COUNT - 1);
        let index = self.verses[c].iter().rposition(|&n| n <= verse).unwrap_or(0);
        self.start(c) + index as f64
    }

    /// The place at `position`, labelled for `speed`.
    pub fn point(&self, position: f64, speed: ScrubSpeed) -> ScrubPoint {
        let c = self.chapter_at(position);
        let numbers = &self.verses[c];
        let index = (position - self.start(c)).floor().clamp(0.0, numbers.len() as f64 - 1.0) as usize;
        let chapter = ChapterIdx(c as u16);
        let book = chapter.book();
        let at_verse = speed == ScrubSpeed::Verse;
        let verse = if at_verse { numbers[index] } else { numbers[0] };
        let section = SECTIONS.iter().rev().find(|s| s.0 <= book.0).map_or("", |s| s.1);
        ScrubPoint {
            position,
            fraction: (position / self.length()).clamp(0.0, 1.0),
            speed,
            chapter_index: chapter.0,
            book: book.0,
            verse,
            reference: if at_verse { format!("{}:{verse}", chapter.display()) } else { chapter.display() },
            section: section.to_string(),
        }
    }

    /// The marks along the rail where the parts of the Bible start.
    pub fn landmarks(&self) -> Vec<ScrubLandmark> {
        SECTIONS
            .iter()
            .filter(|s| s.2)
            .map(|&(book, _, _)| {
                let first = BookId(book).first_chapter();
                ScrubLandmark {
                    fraction: self.start(first.index()) / self.length(),
                    testament: BookId(book) == bible_core::books::FIRST_NT_BOOK,
                }
            })
            .collect()
    }
}

/// One drag along the rail, from the press to letting go.
#[derive(Debug, uniffi::Object)]
pub struct ScrubGesture {
    axis: Arc<ScrubAxis>,
    state: Mutex<Stepped>,
}

#[uniffi::export]
impl ScrubGesture {
    /// A press at height `y` on a track from `track_top`, `track_height` tall, with the thumb
    /// resting at `resting` (an axis position).
    #[uniffi::constructor]
    pub fn new(axis: Arc<ScrubAxis>, resting: f64, y: f64, track_top: f64, track_height: f64) -> Arc<Self> {
        let position = axis.pressed(resting, y, track_top, track_height);
        let state = Stepped::new(position, y, track_height);
        Arc::new(ScrubGesture { axis, state: Mutex::new(state) })
    }

    /// Follows the finger to height `y`, `inward` points in from the rail's inner edge.
    pub fn move_to(&self, y: f64, inward: f64) -> ScrubPoint {
        let mut state = self.state();
        state.move_to(&self.axis, y, inward);
        self.axis.point(state.position, state.speed)
    }

    /// Where the drag is now.
    pub fn point(&self) -> ScrubPoint {
        let state = self.state();
        self.axis.point(state.position, state.speed)
    }
}

impl ScrubGesture {
    fn state(&self) -> MutexGuard<'_, Stepped> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }
}

/// The stepped model: the press is absolute and movement after it relative. Chapter and Verse
/// speed count whole steps of finger travel from where the speed began (`from_y`, `from_count`).
#[derive(Debug)]
struct Stepped {
    speed: ScrubSpeed,
    position: f64,
    rail_height: f64,
    last_y: f64,
    from_y: f64,
    /// At Bible speed an axis position; at Chapter speed a chapter count; at Verse speed a verse
    /// count. Counts sit half a step in, so the finger is mid-step rather than on an edge.
    from_count: f64,
    /// Where the drag last left Verse speed, so dropping back into it in the same chapter
    /// resumes at that verse.
    left_verse: Option<f64>,
}

impl Stepped {
    fn new(position: f64, y: f64, rail_height: f64) -> Self {
        Stepped {
            speed: ScrubSpeed::Bible,
            position,
            rail_height: rail_height.max(1.0),
            last_y: y,
            from_y: y,
            from_count: position,
            left_verse: None,
        }
    }

    fn move_to(&mut self, axis: &ScrubAxis, y: f64, inward: f64) {
        let next = self.speed.at(inward);
        if next != self.speed {
            if self.speed == ScrubSpeed::Verse {
                self.left_verse = Some(self.position);
            }
            self.speed = next;
            self.from_y = self.last_y;
            let chapter = axis.chapter_at(self.position);
            match next {
                ScrubSpeed::Chapter => self.from_count = chapter as f64 + 0.5,
                ScrubSpeed::Verse => {
                    self.position = match self.left_verse {
                        Some(v) if axis.chapter_at(v) == chapter => v,
                        _ => axis.start(chapter) + 0.5,
                    };
                    self.from_count = self.position;
                }
                ScrubSpeed::Bible => self.from_count = self.position,
            }
        }
        self.last_y = y;

        if self.speed == ScrubSpeed::Bible {
            let travelled = (y - self.from_y) / self.rail_height * axis.length();
            self.position = (self.from_count + travelled).clamp(0.0, axis.length());
            return;
        }
        let (step, last) = if self.speed == ScrubSpeed::Chapter {
            (CHAPTER_STEP, CHAPTER_COUNT as f64 - 0.5)
        } else {
            (VERSE_STEP, axis.length() - 0.5)
        };
        let travelled = self.from_count + (y - self.from_y) / step;
        let count = travelled.clamp(0.5, last);
        // Past an end the count stops, and turning back moves it again at once.
        if count != travelled {
            self.from_y = y;
            self.from_count = count;
        }
        if self.speed == ScrubSpeed::Verse {
            self.position = count;
        } else if count.floor() as usize != axis.chapter_at(self.position) {
            self.position = axis.start(count.floor() as usize);
        }
    }
}

#[cfg(test)]
mod tests {
    use bible_core::model::{TranslationBuilder, TranslationMeta};

    use super::*;

    fn psalm(chapter: u8) -> u16 {
        ChapterIdx::new(BookId::PSALMS, chapter).unwrap().0
    }

    #[test]
    fn the_canonical_axis_has_a_stop_for_every_verse() {
        let axis = ScrubAxis::new(None);
        assert_eq!(axis.length(), 31_102.0);
        for c in ChapterIdx::all() {
            assert_eq!(axis.start(c.index() + 1) - axis.start(c.index()), c.kjv_verses() as f64);
            for verse in 1..=c.kjv_verses() {
                let landed = axis.point(axis.position(c.0, verse) + 0.5, ScrubSpeed::Verse);
                assert_eq!((landed.chapter_index, landed.verse), (c.0, verse));
            }
        }
        let first = axis.point(-100.0, ScrubSpeed::Verse);
        assert_eq!((first.chapter_index, first.verse, first.reference.as_str()), (0, 1, "Genesis 1:1"));
        let last = axis.point(axis.length() + 100.0, ScrubSpeed::Verse);
        assert_eq!((last.chapter_index, last.verse, last.fraction), (1188, 21, 1.0));
        assert_eq!(last.reference, "Revelation 22:21");
    }

    #[test]
    fn a_chapter_the_translation_lacks_is_one_stop() {
        let mut b = TranslationBuilder::new(TranslationMeta::default());
        b.begin_book(BookId(42));
        b.begin_chapter(3);
        b.begin_verse(16, 16);
        b.text("For God so loved the world.");
        b.begin_verse(17, 17);
        b.text("For God sent not his Son.");
        let axis = ScrubAxis::new(Some(&b.finish()));
        assert_eq!(axis.length(), (CHAPTER_COUNT - 1 + 2) as f64);
        let john_3 = ChapterIdx::new(BookId(42), 3).unwrap().0;
        assert_eq!(axis.point(axis.position(john_3, 17) + 0.5, ScrubSpeed::Verse).reference, "John 3:17");
        assert_eq!(axis.point(axis.position(john_3, 1) + 0.5, ScrubSpeed::Verse).reference, "John 3:16");
        let genesis = axis.point(0.5, ScrubSpeed::Chapter);
        assert_eq!((genesis.reference.as_str(), genesis.verse), ("Genesis 1", 1));
        assert_eq!(axis.point(1.5, ScrubSpeed::Chapter).reference, "Genesis 2");
    }

    #[test]
    fn points_are_labelled_for_their_speed() {
        let axis = ScrubAxis::new(None);
        let at = axis.position(psalm(23), 4) + 0.5;
        let chapter = axis.point(at, ScrubSpeed::Chapter);
        assert_eq!((chapter.reference.as_str(), chapter.verse), ("Psalm 23", 1));
        assert_eq!(chapter.section, "Wisdom and Poetry");
        let verse = axis.point(at, ScrubSpeed::Verse);
        assert_eq!((verse.reference.as_str(), verse.verse), ("Psalm 23:4", 4));
        let john = ChapterIdx::new(BookId(42), 3).unwrap().0;
        assert_eq!(axis.point(axis.position(john, 16), ScrubSpeed::Bible).section, "Gospels and Acts");
        assert_eq!(axis.point(axis.length(), ScrubSpeed::Bible).section, "General Epistles");
    }

    #[test]
    fn landmarks_mark_the_parts_of_the_bible() {
        let axis = ScrubAxis::new(None);
        let marks = axis.landmarks();
        assert_eq!(marks.len(), 7);
        assert!(marks.windows(2).all(|w| w[0].fraction < w[1].fraction));
        let testament: Vec<&ScrubLandmark> = marks.iter().filter(|m| m.testament).collect();
        assert_eq!(testament.len(), 1);
        // The Old Testament has 23,145 of the canonical grid's verses.
        assert_eq!(testament[0].fraction, 23_145.0 / 31_102.0);
    }

    #[test]
    fn speed_boundaries_and_hysteresis() {
        use ScrubSpeed::*;
        assert_eq!(Bible.at(59.0), Bible);
        assert_eq!(Bible.at(60.0), Chapter);
        assert_eq!(Chapter.at(44.0), Chapter);
        assert_eq!(Chapter.at(43.0), Bible);
        assert_eq!(Chapter.at(140.0), Verse);
        assert_eq!(Verse.at(124.0), Verse);
        assert_eq!(Verse.at(123.0), Chapter);
        assert_eq!(Bible.at(150.0), Verse);
        assert_eq!(Verse.at(0.0), Bible);
    }

    #[test]
    fn a_press_on_the_thumb_picks_it_up_and_elsewhere_jumps() {
        let axis = ScrubAxis::new(None);
        let resting = axis.length() / 4.0;
        // A 600 pt track from y = 100: the thumb rests at 250.
        assert_eq!(axis.pressed(resting, 290.0, 100.0, 600.0), resting);
        assert_eq!(axis.pressed(resting, 400.0, 100.0, 600.0), axis.length() / 2.0);
        assert_eq!(axis.pressed(resting, 0.0, 100.0, 600.0), 0.0);
        assert_eq!(axis.pressed(resting, 900.0, 100.0, 600.0), axis.length());
    }

    #[test]
    fn uneven_chapters_verse_resumption_and_no_snap_back() {
        let axis = ScrubAxis::new(None);
        let chapter = |drag: &Stepped| axis.point(drag.position, ScrubSpeed::Chapter).chapter_index;
        let verse = |drag: &Stepped| axis.point(drag.position, ScrubSpeed::Verse).verse;
        let mut drag = Stepped::new(axis.position(psalm(116), 1), 400.0, 600.0);
        drag.move_to(&axis, 400.0, 60.0);
        drag.move_to(&axis, 411.0, 60.0);
        assert_eq!(chapter(&drag), psalm(116));
        // Psalm 117 has two verses and takes as much travel as any other.
        drag.move_to(&axis, 412.0, 60.0);
        assert_eq!(chapter(&drag), psalm(117));
        drag.move_to(&axis, 436.0, 60.0);
        assert_eq!(chapter(&drag), psalm(118));
        drag.move_to(&axis, 436.0, 140.0);
        drag.move_to(&axis, 500.0, 140.0);
        assert_eq!(verse(&drag), 5);
        // Out to Chapter speed and back in without leaving the chapter: the same verse.
        drag.move_to(&axis, 500.0, 60.0);
        drag.move_to(&axis, 508.0, 60.0);
        drag.move_to(&axis, 508.0, 140.0);
        assert_eq!(verse(&drag), 5);
        // Out to Bible speed: nothing moves until the finger does.
        let previous = drag.position;
        drag.move_to(&axis, 508.0, 0.0);
        assert_eq!(drag.position, previous);
        drag.move_to(&axis, 568.0, 0.0);
        assert!((drag.position - (previous + axis.length() / 10.0)).abs() < 0.001);
    }

    #[test]
    fn finer_speeds_turn_back_at_once_after_overshooting() {
        let axis = ScrubAxis::new(None);
        let mut drag = Stepped::new(0.0, 100.0, 600.0);
        drag.move_to(&axis, 100.0, 140.0);
        drag.move_to(&axis, -200.0, 140.0);
        assert_eq!(drag.position, 0.5);
        drag.move_to(&axis, -192.0, 140.0);
        assert_eq!(drag.position, 1.0);
        drag.move_to(&axis, 1_000_000.0, 140.0);
        assert_eq!(drag.position, axis.length() - 0.5);
        drag.move_to(&axis, 1_000_000.0 - 16.0, 140.0);
        assert_eq!(drag.position, axis.length() - 1.5);
    }
}
