fn main() {}

#[cfg(test)]
mod test {
    use parity_scale_codec::{Compact, Encode};

    #[test]
    fn encode_optional_bool() {
        let opt_bool: Option<bool> = Some(true);
        println!("{:?}", opt_bool.encode())
    }

    #[test]
    fn encoding_compact() {
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
        #[derive(Encode)]
        struct Str<N, O> {
            str: String,
            number: N,
            opt: Option<O>,
        }

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

    #[test]
    fn encode_vectors_and_slices() {
        let v1 = vec![Some(1), Some(2), Some(10000)];
        println!("{:?}", v1.encode());
        println!("{:?}", v1.size_hint());

        let v2: &[Result<String, u64>] = &vec![
            Ok(String::from("ok!")),
            Err(100),
            Ok(String::from("this is an ok")),
            Err(u64::MAX),
        ];

        println!("{:?}", v2.size_hint());
        println!("{:?}", v2.encode());
    }

    #[test]
    fn encoding_tuple() {
        let tuple: (u32, u64, bool, Result<String, String>) =
            (9090 as u32, 9090 as u64, true, Ok(String::from("ok!")));

        println!("{:?}", tuple.size_hint());
        println!("{:?}", tuple.encode());
    }
}
