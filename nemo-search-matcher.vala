namespace GeditNemoPlugin {
    class RegexFind : Object, IMatcher {
        private Regex re;

        public RegexFind (string pattern, bool ignore_case) throws Error {
            var flags = RegexCompileFlags.OPTIMIZE;

            if (ignore_case)
                flags |= RegexCompileFlags.CASELESS;

            re = new Regex (pattern, flags);
        }

        public bool has_match (uint8 *text, size_t text_length, size_t pos, ref Range match) {
            MatchInfo info;
            int casted_pos;

            // Prevent an integer overflow when downcasting from size_t to int
            if (pos > int.MAX) {
                casted_pos = 0;
                text += pos;
            }
            else {
                casted_pos = (int)pos;
            }

            // Avoid strdup-ing the whole buffer
            unowned string str = (string)text;

            // Pass the text length as str isn't null terminated
            try {
                if (!re.match_full (str, (ssize_t)text_length, casted_pos, 0, out info))
                    return false;
            }
            catch (RegexError err) {
                warning (err.message);
                return false;
            }

            info.fetch_pos (0, out match.from, out match.to);

            return true;
        }
    }

    class BoyerMooreHorspool : Object, IMatcher {
        private string pattern;
        private int bad_char_shift[256];

        private bool ignore_case;

        public BoyerMooreHorspool (string pattern_, bool ignore_case_) {
            pattern = pattern_;
            ignore_case = ignore_case_;

            for (int i = 0; i < 256; i++)
                bad_char_shift[i] = pattern.length;

            for (int i = 0; i < pattern.length - 1; i++) {
                if (ignore_case) {
                    bad_char_shift[Posix.toupper(pattern[i])] = pattern.length - 1 - i;
                    bad_char_shift[Posix.tolower(pattern[i])] = pattern.length - 1 - i;
                }
                else {
                    bad_char_shift[pattern[i]] = pattern.length - 1 - i;
                }
            }
        }

        public bool has_match (uint8 *text, size_t text_length, size_t pos, ref Range match) {
            uint i = 0;

            text += pos;
            text_length -= pos;

            if (text_length < pattern.length)
                return false;

            while (i <= text_length - pattern.length) {
                for (int j = pattern.length - 1; j >= 0; j--) {
                    // Check for a match backwards
                    if (ignore_case) {
                        if (Posix.tolower(text[i + j]) != Posix.tolower(pattern[j]))
                            break;
                    }
                    else {
                        if (text[i + j] != pattern[j])
                            break;
                    }
                    // The whole needle has been matched!
                    if (j == 0) {
                        match.from = pos + i;
                        match.to = match.from + pattern.length;
                        return true;
                    }
                }

                // Jump ahead in the buffer
                i += bad_char_shift[text[i + pattern.length - 1]];
            }

            return false;
        }
    }
}
