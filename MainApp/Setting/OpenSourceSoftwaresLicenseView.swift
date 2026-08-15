//
//  OpenSourceSoftWaresLicenseView.swift
//  MainApp
//
//  Created by ensan on 2020/09/21.
//  Copyright © 2020 ensan. All rights reserved.
//

import Foundation
import KeyboardViews
import SwiftUI

struct OpenSourceSoftwaresLicenseView: View {
    private let license_mecab = """
    MeCab is copyrighted free software by Taku Kudo <taku@chasen.org> and
    Nippon Telegraph and Telephone Corporation, and is released under
    any of the GPL (see the file GPL), the LGPL (see the file LGPL), or the
    BSD License (see the file BSD).
    """

    // Copaky: llama.cpp and marisa-trie/SwiftyMarisa ship inside the binary because the converter's
    // ZenzaiCPU trait links them, even though Zenzai (neural conversion) is not invoked in v0.1 —
    // both are attributed here for that reason.
    // llama.cppとmarisa-trie/SwiftyMarisaは変換エンジンのZenzaiCPUトレイト経由でバイナリに含まれるため、
    // v0.1ではZenzai（ニューラル変換）を呼び出していなくても、その理由でここに表記する。
    private let license_llama_cpp = """
    MIT License

    Copyright (c) 2023-2024 The ggml authors

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """

    private let license_swiftymarisa = """
    SwiftyMarisa is dual-licensed under the BSD 2-clause license and the LGPL.

    * The BSD 2-clause license

    Copyright (c) 2016, Vladimir Solomenchuk
    All rights reserved.

    Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

    - Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    - Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
    """

    private let license_marisa_trie = """
    libmarisa and its command line tools are licensed under BSD-2-Clause OR LGPL-2.1-or-later.

    The BSD 2-clause license

    Copyright (c) 2010-2025, Susumu Yata
    All rights reserved.

    Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

    - Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    - Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
    """

    private let license_ipadic = """
    Copyright 2000, 2001, 2002, 2003 Nara Institute of Science
    and Technology.  All Rights Reserved.

    Use, reproduction, and distribution of this software is permitted.
    Any copy of this software, whether in its original form or modified,
    must include both the above copyright notice and the following
    paragraphs.

    Nara Institute of Science and Technology (NAIST),
    the copyright holders, disclaims all warranties with regard to this
    software, including all implied warranties of merchantability and
    fitness, in no event shall NAIST be liable for
    any special, indirect or consequential damages or any damages
    whatsoever resulting from loss of use, data or profits, whether in an
    action of contract, negligence or other tortuous action, arising out
    of or in connection with the use or performance of this software.

    A large portion of the dictionary entries
    originate from ICOT Free Software.  The following conditions for ICOT
    Free Software applies to the current dictionary as well.

    Each User may also freely distribute the Program, whether in its
    original form or modified, to any third party or parties, PROVIDED
    that the provisions of Section 3 ("NO WARRANTY") will ALWAYS appear
    on, or be attached to, the Program, which is distributed substantially
    in the same form as set out herein and that such intended
    distribution, if actually made, will neither violate or otherwise
    contravene any of the laws and regulations of the countries having
    jurisdiction over the User or the intended distribution itself.

    NO WARRANTY

    The program was produced on an experimental basis in the course of the
    research and development conducted during the project and is provided
    to users as so produced on an experimental basis.  Accordingly, the
    program is provided without any warranty whatsoever, whether express,
    implied, statutory or otherwise.  The term "warranty" used herein
    includes, but is not limited to, any warranty of the quality,
    performance, merchantability and fitness for a particular purpose of
    the program and the nonexistence of any infringement or violation of
    any right of any third party.

    Each user of the program will agree and understand, and be deemed to
    have agreed and understood, that there is no warranty whatsoever for
    the program and, accordingly, the entire risk arising from or
    otherwise connected with the program is assumed by the user.

    Therefore, neither ICOT, the copyright holder, or any other
    organization that participated in or was otherwise related to the
    development of the program and their respective officials, directors,
    officers and other employees shall be held liable for any and all
    damages, including, without limitation, general, special, incidental
    and consequential damages, arising out of or otherwise in connection
    with the use or inability to use the program or any product, material
    or result produced or otherwise obtained by using the program,
    regardless of whether they have been advised of, or otherwise had
    knowledge of, the possibility of such damages at any time during the
    project or thereafter.  Each user will be deemed to have agreed to the
    foregoing by his or her commencement of use of the program.  The term
    "use" as used herein includes, but is not limited to, the use,
    modification, copying and distribution of the program and the
    production of secondary products from the program.

    In the case where the program, whether in its original form or
    modified, was distributed or delivered to or received by a user from
    any person, organization or entity other than ICOT, unless it makes or
    grants independently of ICOT any specific warranty to the user in
    writing, such person, organization or entity, will also be exempted
    from and not be held liable to the user for any such damages as noted
    above as far as the program is concerned.
    """

    var body: some View {
        Form {
            Section {
                Text("本アプリケーションは多くのオープンソースソフトウェアを用いて作成されています。この場を借りて感謝申し上げます。")
            }
            Group {
                Section {
                    Text(verbatim: "SudachiDict").font(.title).padding()
                    Text("本アプリケーションは基礎的な語彙の基盤としてSudachiDictを使用しています。")

                    FallbackLink("License", destination: "https://github.com/WorksApplications/SudachiDict/blob/develop/LICENSE-2.0.txt")
                    FallbackLink(verbatim: "SudachiDict", destination: "https://github.com/WorksApplications/SudachiDict")
                }
                Section {
                    Text(verbatim: "IPAdic").font(.title).padding()
                    Text("本アプリケーションは基礎的な語彙の基盤としてIPAdicを使用しています。")
                    Text(license_ipadic)
                }
                // Copaky: the bundled Italian frequency lexicon (CC BY) requires attribution in the
                // shipped app, not only in the repository. / 同梱イタリア語辞書のCC BY表記。
                Section {
                    Text(verbatim: "Leipzig Corpora Collection").font(.title).padding()
                    Text("本アプリケーションはイタリア語の予測入力のため、Leipzig Corpora Collection由来の頻度辞書を使用しています（CC BY・© Universität Leipzig / Sächsische Akademie der Wissenschaften / InfAI）。")
                    FallbackLink(verbatim: "Leipzig Corpora Collection", destination: "https://wortschatz.uni-leipzig.de/en")
                    FallbackLink("License", destination: "https://wortschatz.uni-leipzig.de/en/usage")
                }
                Section {
                    Text(verbatim: "MeCab").font(.title).padding()
                    Text("本アプリケーションは形態素解析器としてMeCabを使用しています。")
                    FallbackLink(verbatim: "MeCab: Yet Another Part-of-Speech and Morphological Analyzer", destination: "https://taku910.github.io/mecab/")
                    Text(license_mecab)
                }
                Section {
                    Text(verbatim: "mecab-ipadic-NEologd").font(.title).padding()
                    Text("本アプリケーションは固有名詞などの解析のためmecab-ipadic-NEologdを使用しています。")
                    FallbackLink("License", destination: "https://github.com/neologd/mecab-ipadic-neologd/blob/master/COPYING")
                    FallbackLink(verbatim: "mecab-ipadic-NEologd : Neologism dictionary for MeCab", destination: "https://github.com/neologd/mecab-ipadic-neologd")
                }
                Section {
                    Text(verbatim: "Mozc").font(.title).padding()
                    Text("本アプリケーションはMozcの一部のデータを利用しています。")
                    FallbackLink(verbatim: "BSD 3-Clause \"New\" or \"Revised\" License", destination: "https://github.com/google/mozc/blob/master/LICENSE")
                    FallbackLink(verbatim: "Mozc", destination: "https://github.com/google/mozc")
                    Text(verbatim: "Copyright 2010-2022, Google Inc.")
                }
                Section {
                    Text(verbatim: "japanese-word2vec-model-builder").font(.title).padding()
                    Text("本アプリケーションは変換精度の向上のためjapanese-word2vec-model-builderを使用しています。")
                    FallbackLink("License", destination: "https://github.com/shiroyagicorp/japanese-word2vec-model-builder/blob/master/LICENSE")
                    FallbackLink(verbatim: "Japanese Word2Vec Model Builder", destination: "https://github.com/shiroyagicorp/japanese-word2vec-model-builder")
                }

                Group {
                    Section {
                        Text(verbatim: "Emoji-IME-Dictionary").font(.title).padding()
                        Text("本アプリケーションは絵文字への変換候補を表示するためにEmoji-IME-Dictionaryのデータを使用しています。")
                        FallbackLink("License", destination: "https://github.com/peaceiris/emoji-ime-dictionary/blob/main/LICENSE")
                        FallbackLink(verbatim: "Emoji-IME-Dictionary", destination: "https://github.com/peaceiris/emoji-ime-dictionary")
                    }

                    Section {
                        Text(verbatim: "Kaomojitoka to Google IME Dictionary").font(.title).padding()
                        Text("本アプリケーションは顔文字への変換候補を表示するためにKaomojitoka to Google IME Dictionaryのデータを使用しています。")
                        FallbackLink("License", destination: "https://github.com/nikukyugamer/kaomojitoka-to-google-ime-dictionary/blob/master/LICENSE")
                        FallbackLink(
                            verbatim: "Kaomojitoka to Google IME Dictionary",
                            destination: "https://github.com/nikukyugamer/kaomojitoka-to-google-ime-dictionary"
                        )
                    }

                    Section {
                        Text(verbatim: "Kaomojic").font(.title).padding()
                        Text("本アプリケーションは顔文字への変換候補を表示するためにKaomojicのデータを使用しています。")
                        FallbackLink("License", destination: "https://github.com/mika-f/kaomojic/blob/develop/LICENSE")
                        FallbackLink(verbatim: "Kaomojic", destination: "https://github.com/mika-f/kaomojic")
                    }
                }

                Section {
                    Text(verbatim: "CustardKit").font(.title).padding()
                    Text("本アプリケーションで利用可能なカスタムタブのデータ構造の記述をCustardKitとしてオープンソースで公開し、アプリ内でも使用しています。")
                    FallbackLink("License", destination: "https://github.com/azooKey/CustardKit/blob/main/LICENSE")
                    FallbackLink(
                        verbatim: "CustardKit",
                        destination: "https://github.com/azooKey/CustardKit"
                    )
                }
                Group {
                    Section {
                        Text(verbatim: "Swift Algorithms").font(.title).padding()
                        Text("本アプリケーションはSwift Algorithmsを使用しています。")
                        FallbackLink(verbatim: "Apache License 2.0", destination: "https://github.com/apple/swift-algorithms/blob/main/LICENSE.txt")
                        FallbackLink(
                            verbatim: "Swift Algorithms",
                            destination: "https://github.com/apple/swift-algorithms"
                        )
                    }
                    Section {
                        Text(verbatim: "Swift Collections").font(.title).padding()
                        Text("本アプリケーションはSwift Collectionsを使用しています。")
                        FallbackLink(verbatim: "Apache License 2.0", destination: "https://github.com/apple/swift-collections/blob/main/LICENSE.txt")
                        FallbackLink(
                            verbatim: "Swift Collections",
                            destination: "https://github.com/apple/swift-collections"
                        )
                    }
                    Section {
                        Text(verbatim: "llama.cpp").font(.title).padding()
                        Text("本アプリケーションは変換エンジンのZenzaiCPUトレイト経由でllama.cppをバイナリに同梱していますが、v0.1ではまだ呼び出していません。")
                        FallbackLink(verbatim: "MIT License", destination: "https://github.com/ggml-org/llama.cpp/blob/master/LICENSE")
                        FallbackLink(
                            verbatim: "llama.cpp",
                            destination: "https://github.com/ggml-org/llama.cpp"
                        )
                        Text(verbatim: "Prebuilt xcframework: https://github.com/azooKey/llama.cpp")
                        Text(license_llama_cpp)
                    }
                    Section {
                        Text(verbatim: "SwiftyMarisa / marisa-trie").font(.title).padding()
                        Text("本アプリケーションは変換エンジンのZenzaiCPUトレイト経由でSwiftyMarisa（marisa-trieのSwiftラッパー）をバイナリに同梱していますが、v0.1ではまだ呼び出していません。")
                        FallbackLink(verbatim: "BSD 2-Clause License (SwiftyMarisa)", destination: "https://github.com/ensan-hcl/SwiftyMarisa/blob/master/LICENSE.md")
                        FallbackLink(
                            verbatim: "SwiftyMarisa",
                            destination: "https://github.com/ensan-hcl/SwiftyMarisa"
                        )
                        Text(license_swiftymarisa)
                        FallbackLink(verbatim: "marisa-trie", destination: "https://github.com/s-yata/marisa-trie")
                        Text(license_marisa_trie)
                    }
                }
            }
            Section {
                HStack {
                    FunnyAzooKeyIcon()
                    Spacer()
                    Text("Copakyを使ってくれてありがとう！")
                }
            }
        }
        .multilineTextAlignment(.leading)
        .navigationBarTitle(Text("オープンソースソフトウェア"), displayMode: .inline)
    }
}

private struct FunnyAzooKeyIcon: View {
    init(stage: Stage = .normal) {
        self._stage = .init(initialValue: stage)
    }

    struct NormalAnimationValue {
        // degrees
        var angle: Double = -10
    }
    struct KingAnimationValue {
        // degrees
        var yAngle: Double = -10
        var scale: Double = 1.0
    }
    struct FireAnimationValue {
        // degrees
        var yAngle: Double = 0
        var scale: Double = 1.0
    }
    enum Stage {
        case normal
        case king
        case fire
    }
    @Namespace private var namespace
    @State private var stage: Stage = .normal

    private var iconCore: some View {
        AzooKeyIcon(fontSize: 60)
            .matchedGeometryEffect(id: "icon", in: namespace)
    }

    var body: some View {
        if #available(iOS 17, *) {
            switch stage {
            case .normal:
                iconCore
                    .keyframeAnimator(initialValue: NormalAnimationValue()) { content, value in
                        content
                            .rotationEffect(Angle(degrees: value.angle))
                    } keyframes: { _ in
                        KeyframeTrack(\.angle) {
                            CubicKeyframe(10, duration: 0.5)
                            CubicKeyframe(-10, duration: 0.5)
                        }
                    }
                    .onTapGesture {
                        withAnimation {
                            self.stage = Bool.random() ? .king : .fire
                        }
                    }
            case .king:
                AzooKeyIcon(fontSize: 60, looks: .king)
                    .matchedGeometryEffect(id: "icon", in: namespace)
                    .keyframeAnimator(initialValue: KingAnimationValue()) { content, value in
                        content
                            .rotationEffect(Angle(degrees: value.yAngle))
                            .scaleEffect(value.scale)
                    } keyframes: { _ in
                        KeyframeTrack(\.yAngle) {
                            CubicKeyframe(10, duration: 0.5)
                            CubicKeyframe(-10, duration: 0.5)
                        }
                        KeyframeTrack(\.scale) {
                            SpringKeyframe(1, duration: 0.2)
                            SpringKeyframe(1.4, duration: 0.6)
                            SpringKeyframe(1, duration: 0.2)
                        }
                    }
                    .onTapGesture {
                        withAnimation {
                            self.stage = .normal
                        }
                    }
            case .fire:
                AzooKeyIcon(fontSize: 60, looks: .fire)
                    .matchedGeometryEffect(id: "icon", in: namespace)
                    .keyframeAnimator(initialValue: FireAnimationValue()) { content, value in
                        content
                            .rotationEffect(Angle(degrees: value.yAngle))
                            .scaleEffect(value.scale)
                    } keyframes: { _ in
                        KeyframeTrack(\.yAngle) {
                            SpringKeyframe(20, duration: 0.8)
                            CubicKeyframe(0, duration: 0.2)
                        }
                    }
                    .onTapGesture {
                        withAnimation {
                            self.stage = .normal
                        }
                    }
            }
        } else {
            iconCore
        }
    }
}

#Preview {
    VStack {
        FunnyAzooKeyIcon(stage: .normal)
        FunnyAzooKeyIcon(stage: .king)
        FunnyAzooKeyIcon(stage: .fire)
    }
}
