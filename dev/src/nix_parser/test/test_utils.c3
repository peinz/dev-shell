module test_utils;

import std::time::datetime;

fn void int_to_dstring(DString* ds, int val, bool zero_pad) {
  if (val == 0) {
    ds.append("0");
    return;
  }

  if (zero_pad && val < 10) {
    ds.append("0");
  }

  char[16] buf;
  usz len = 0;
  int n = val;

  if (n < 0) {
    ds.append("-");
    n = -n;
  }

  while (n > 0) {
    buf[len] = (char)('0' + (n % 10));
    len++;
    n = n / 10;
  }

  for (usz i = len; i > 0; i--) {
    ds.append(buf[i - 1]);
  }
}

fn void get_current_timestamp(DString* out_timestamp) {
  DateTime dt = datetime::now();

  int year_val = (int)dt.year;
  int month_val = (int)dt.month + 1;
  int day_val = (int)(char)dt.day;
  int hour_val = (int)(char)dt.hour;
  int min_val = (int)(char)dt.min;
  int sec_val = (int)(char)dt.sec;

  int_to_dstring(out_timestamp, year_val, false);
  out_timestamp.append("-");
  int_to_dstring(out_timestamp, month_val, true);
  out_timestamp.append("-");
  int_to_dstring(out_timestamp, day_val, true);
  out_timestamp.append("T");
  int_to_dstring(out_timestamp, hour_val, true);
  out_timestamp.append(":");
  int_to_dstring(out_timestamp, min_val, true);
  out_timestamp.append(":");
  int_to_dstring(out_timestamp, sec_val, true);
}

fn String flatten_for_comment(String s) {
  DString result = dstring::temp();
  for (usz i = 0; i < s.len; i++) {
    char c = s[i];
    if (c == '\n' || c == '\t') {
      result.append(' ');
    } else {
      result.append(c);
    }
  }
  return result.str_view();
}
