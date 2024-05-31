use parity_scale_codec::{Decode, Encode};

#[derive(Decode, Encode)]
struct Str<N, O> {
    str: String,
    number: N,
    opt: Option<O>,
}

fn main() {
    println!("Hello, world!");
}

#[cfg(test)]
mod test {
    use parity_scale_codec::{Compact, Encode};

    use crate::Str;

    #[test]
    fn encode_optional_bool() {
        let opt_bool: Option<bool> = Some(true);
        println!("{:?}", opt_bool.encode())
    }

    #[test]
    fn encoding_compact_u8() {
        let compact: Compact<u128> = Compact(u128::MAX);
        println!("{:?}", compact.encode());
        println!("{:?}", compact.size_hint());
    }

    #[test]
    fn encoding_integers() {
        println!("{:?}", i64::MAX.encode());
    }

    #[test]
    fn encoding_struct() {
        let vars = vec![
            Str::<u64, bool> {
                str: String::from("some_name"),
                number: 10,
                opt: Some(true),
            },
            Str::<u64, bool> {
                str: String::from("some_name"),
                number: 10,
                opt: Some(false),
            },
            Str::<u64, bool> {
                str: String::from("some_name"),
                number: 10,
                opt: None,
            },
        ];

        for v in vars {
            println!("{:?}", v.encode());
        }
    }

    #[test]
    fn encoding_result_type() {
        let a: Result<String, String> = Ok(String::from("eclesio"));
        println!("{:?}", a.encode());

        #[derive(Encode)]
        struct StrWithResult {
            result: Result<u64, String>,
            cmp: Compact<u64>,
        }

        let my_ok: StrWithResult = StrWithResult {
            result: Ok(100),
            cmp: Compact(u16::MAX as u64),
        };

        println!("{:?}", my_ok.encode());

        let my_ok: StrWithResult = StrWithResult {
            result: Err(String::from("fail")),
            cmp: Compact(u8::MAX as u64),
        };

        println!("{:?}", my_ok.encode());
    }
}
